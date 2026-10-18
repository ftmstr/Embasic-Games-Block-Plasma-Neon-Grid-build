import 'dart:convert';
import 'dart:io';

import '../domain/game_engine.dart';
import 'game_repository.dart';

enum _ReadKind { missing, valid, corrupt, unsupported }

class _ReadResult {
  const _ReadResult(this.kind, [this.state]);
  final _ReadKind kind;
  final GameState? state;
}

/// Transaction-like snapshot writes: write + flush temp, rotate last committed
/// primary to backup, then rename temp to primary. The backup is retained on
/// recovery so a corrupt primary cannot destroy the last good state.
class FileGameRepository implements GameRepository {
  FileGameRepository(this.directory);

  static const primaryName = 'game-state.json';
  static const backupName = 'game-state.backup.json';
  static const pendingName = 'game-state.pending.json';
  static const maxSnapshotBytes = 64 * 1024;

  final Directory directory;
  Future<void> _tail = Future<void>.value();
  bool _avoidBackupRotation = false;

  File get _primary => File('${directory.path}/$primaryName');
  File get _backup => File('${directory.path}/$backupName');
  File get _pending => File('${directory.path}/$pendingName');

  Future<_ReadResult> _read(File file) async {
    if (!await file.exists()) return const _ReadResult(_ReadKind.missing);
    try {
      // A 64-cell game snapshot should never require a large JSON payload.
      // Bound malformed reads before allocating/decoding attacker-controlled data.
      if (await file.length() > maxSnapshotBytes) {
        return const _ReadResult(_ReadKind.corrupt);
      }
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return const _ReadResult(_ReadKind.corrupt);
      }
      try {
        return _ReadResult(_ReadKind.valid, GameState.fromJson(decoded));
      } on FormatException catch (error) {
        if (error.message == 'Unsupported save version') {
          return const _ReadResult(_ReadKind.unsupported);
        }
        return const _ReadResult(_ReadKind.corrupt);
      }
    } on FormatException {
      return const _ReadResult(_ReadKind.corrupt);
    }
  }

  @override
  Future<LoadResult> load() async {
    try {
      await _tail;
      final primary = await _read(_primary);
      final backup = await _read(_backup);
      // Do not downgrade data written by a newer version, even when an
      // older valid backup happens to exist. Require explicit reset instead.
      if (primary.kind == _ReadKind.unsupported ||
          backup.kind == _ReadKind.unsupported) {
        _avoidBackupRotation = true;
        return const LoadResult(LoadStatus.unsupportedVersion);
      }
      if (primary.kind == _ReadKind.valid) {
        _avoidBackupRotation = false;
        return LoadResult(LoadStatus.loaded, primary.state);
      }
      if (backup.kind == _ReadKind.valid) {
        _avoidBackupRotation = true;
        return LoadResult(LoadStatus.recovered, backup.state);
      }
      if (primary.kind == _ReadKind.missing &&
          backup.kind == _ReadKind.missing) {
        return const LoadResult(LoadStatus.empty);
      }
      _avoidBackupRotation = true;
      return const LoadResult(LoadStatus.corrupt);
    } on FileSystemException {
      _avoidBackupRotation = true;
      return const LoadResult(LoadStatus.unavailable);
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final pending = _tail.then((_) => operation());
    _tail = pending.then((_) {}, onError: (Object _, StackTrace __) {});
    return pending;
  }

  @override
  Future<void> save(GameState snapshot) => _enqueue(() async {
    await directory.create(recursive: true);
    // Revalidate existing disk data on every write. Calling save() before
    // load() must never rotate malformed/future-version primary over good
    // backup. Unknown newer versions and unrecoverable corruption require
    // an explicit clear() before a new game may be stored.
    final primary = await _read(_primary);
    final backup = await _read(_backup);
    if (primary.kind == _ReadKind.unsupported ||
        backup.kind == _ReadKind.unsupported ||
        (primary.kind != _ReadKind.valid &&
            backup.kind != _ReadKind.valid &&
            (primary.kind == _ReadKind.corrupt ||
             backup.kind == _ReadKind.corrupt))) {
      throw StateError('Existing save requires explicit reset');
    }
    final preserveBackup = _avoidBackupRotation ||
        (primary.kind != _ReadKind.valid &&
            backup.kind == _ReadKind.valid);
    final data = jsonEncode(snapshot.toJson());
    await _pending.writeAsString(data, flush: true);
    if (preserveBackup) {
      // The old primary is invalid/missing; never replace the valid backup.
      if (await _primary.exists()) await _primary.delete();
    } else if (primary.kind == _ReadKind.valid) {
      // The primary is verified before it can replace the older backup.
      // If interrupted after rename, load() recovers from backup.
      if (await _backup.exists()) await _backup.delete();
      await _primary.rename(_backup.path);
    }
    await _pending.rename(_primary.path);
    _avoidBackupRotation = false;
  });

  @override
  Future<void> clear() => _enqueue(() async {
    for (final file in [_pending, _primary, _backup]) {
      if (await file.exists()) await file.delete();
    }
    _avoidBackupRotation = false;
  });
}
