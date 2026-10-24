import 'dart:convert';
import 'dart:io';

import 'package:block_plasma_neon_grid/data/game_repository.dart';
import 'package:block_plasma_neon_grid/data/local_game_repository.dart';
import 'package:block_plasma_neon_grid/domain/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

GameState afterFirstMove(int seed) {
  final start = GameEngine.newGame(seed: seed, bestScore: 100);
  final moved = GameEngine.applyMove(start, MoveAction(
    trayIndex: 0, row: 0, col: 0, expectedTurnId: start.turnId,
  ));
  expect(moved.accepted, isTrue);
  return moved.state;
}

void expectSame(GameState? actual, GameState expected) {
  expect(actual, isNotNull);
  expect(actual!.toJson(), expected.toJson());
}

void main() {
  late Directory directory;
  late FileGameRepository repository;
  File primary() => File('${directory.path}/${FileGameRepository.primaryName}');
  File backup() => File('${directory.path}/${FileGameRepository.backupName}');
  File pending() => File('${directory.path}/${FileGameRepository.pendingName}');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('block-plasma-save-test-');
    repository = FileGameRepository(directory);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('SAVE-01 missing local save returns explicit empty status', () async {
    final outcome = await repository.load();
    expect(outcome.status, LoadStatus.empty);
    expect(outcome.state, isNull);
  });

  test('SAVE-02 exact committed state survives independent repository reload',
      () async {
    final committed = afterFirstMove(77);
    await repository.save(committed);
    final restored = await FileGameRepository(directory).load();
    expect(restored.status, LoadStatus.loaded);
    expectSame(restored.state, committed);
    expect(restored.state!.turnId, 1);
    expect(restored.state!.bestScore, 100);
  });

  test('SAVE-03 corrupt primary restores last verified backup', () async {
    final earlier = afterFirstMove(17);
    final later = afterFirstMove(99);
    await repository.save(earlier);
    await repository.save(later);
    await primary().writeAsString('{truncated');
    final recovered = await FileGameRepository(directory).load();
    expect(recovered.status, LoadStatus.recovered);
    expectSame(recovered.state, earlier);
  });

  test('SAVE-04 repairing a corrupt primary must not overwrite good backup',
      () async {
    final good = afterFirstMove(21);
    await repository.save(good);
    await repository.save(afterFirstMove(45));
    await primary().writeAsString('bad');
    final freshRepository = FileGameRepository(directory);
    expect((await freshRepository.load()).status, LoadStatus.recovered);
    final newState = afterFirstMove(61);
    await freshRepository.save(newState);
    expectSame((await FileGameRepository(directory).load()).state, newState);
    expectSame(GameState.fromJson(jsonDecode(await backup().readAsString())
        as Map<String, dynamic>), good);
  });

  test('SAVE-05 both snapshots corrupt returns clear failure without throwing',
      () async {
    await primary().writeAsString('bad');
    await backup().writeAsString('also bad');
    final result = await repository.load();
    expect(result.status, LoadStatus.corrupt);
    expect(result.state, isNull);
  });

  test('SAVE-06 newer unsupported schema fails explicitly and stays intact',
      () async {
    final unsupported = afterFirstMove(11).toJson()
      ..['schemaVersion'] = GameState.schemaVersion + 1;
    await primary().writeAsString(jsonEncode(unsupported));
    final result = await repository.load();
    expect(result.status, LoadStatus.unsupportedVersion);
    expect(result.state, isNull);
    expect(jsonDecode(await primary().readAsString()), unsupported);
  });

  test('SAVE-07 interrupted pending write must never replace committed turn',
      () async {
    final committed = afterFirstMove(10);
    await repository.save(committed);
    await pending().writeAsString(jsonEncode(afterFirstMove(20).toJson()));
    final result = await FileGameRepository(directory).load();
    expect(result.status, LoadStatus.loaded);
    expectSame(result.state, committed);
  });

  test('SAVE-08 concurrent saves are serialized in submission order',
      () async {
    final first = afterFirstMove(1);
    final second = afterFirstMove(2);
    await Future.wait([repository.save(first), repository.save(second)]);
    final result = await FileGameRepository(directory).load();
    expectSame(result.state, second);
  });

  test('SAVE-09 resumed seeded RNG makes identical next transition', () async {
    final previous = afterFirstMove(123456);
    await repository.save(previous);
    final restored = (await FileGameRepository(directory).load()).state!;
    final available = restored.tray.indexWhere((p) => p != null);
    expect(available, greaterThanOrEqualTo(0));
    MoveResult? expected;
    MoveResult? actual;
    for (var row = 0; row < 8 && expected == null; row++) {
      for (var col = 0; col < 8; col++) {
        if (GameEngine.canPlace(previous, previous.tray[available]!, row, col)) {
          final move = MoveAction(trayIndex: available, row: row, col: col,
              expectedTurnId: previous.turnId);
          expected = GameEngine.applyMove(previous, move);
          actual = GameEngine.applyMove(restored, move);
          break;
        }
      }
    }
    expect(expected, isNotNull);
    expectSame(actual!.state, expected!.state);
    expect(actual.state.rngState, expected.state.rngState);
  });

  test('SAVE-10 stale turn after reload does not modify snapshot', () async {
    final snapshot = afterFirstMove(72);
    await repository.save(snapshot);
    final state = (await FileGameRepository(directory).load()).state!;
    final rejected = GameEngine.applyMove(state, const MoveAction(
      trayIndex: 0, row: 0, col: 0, expectedTurnId: 0,
    ));
    expect(rejected.accepted, isFalse);
    expect(rejected.error, MoveError.staleTurn);
    expect(identical(state, rejected.state), isTrue);
  });

  test('SAVE-11 malformed color values and RNG range are rejected', () {
    final snapshot = afterFirstMove(19).toJson();
    snapshot['board'] = List<int?>.of(snapshot['board'] as List<int?>)
      ..[0] = 999;
    expect(() => GameState.fromJson(snapshot), throwsFormatException);
    final badRng = afterFirstMove(19).toJson()..['rngState'] = -1;
    expect(() => GameState.fromJson(badRng), throwsFormatException);
  });

  test('SAVE-13 future-version primary must supersede valid old backup', () async {
    final old = afterFirstMove(14);
    await repository.save(old);
    await repository.save(old); // Establish valid rollback backup.
    final newer = old.toJson()..['schemaVersion'] = 2;
    await primary().writeAsString(jsonEncode(newer));
    final loaded = await FileGameRepository(directory).load();
    expect(loaded.status, LoadStatus.unsupportedVersion);
    expect(loaded.state, isNull);
    expect(jsonDecode(await primary().readAsString()), newer);
    expectSame(GameState.fromJson(
      jsonDecode(await backup().readAsString()) as Map<String, dynamic>,
    ), old);
  });

  test('SAVE-14 uninspected unsupported primary refuses save', () async {
    final newer = afterFirstMove(44).toJson()..['schemaVersion'] = 2;
    await primary().writeAsString(jsonEncode(newer));
    await expectLater(repository.save(afterFirstMove(12)), throwsStateError);
    expect(jsonDecode(await primary().readAsString()), newer);
  });

  test('SAVE-15 pre-load save cannot overwrite valid backup with corrupt primary', () async {
    final good = afterFirstMove(16);
    await repository.save(good);
    await repository.save(afterFirstMove(67));
    await primary().writeAsString('broken main');
    final fresh = FileGameRepository(directory);
    await fresh.save(afterFirstMove(24));
    final backupMap = jsonDecode(await backup().readAsString()) as Map<String, dynamic>;
    expectSame(GameState.fromJson(backupMap), good);
  });

  test('SAVE-16 interrupted rotation backup survives with orphan pending', () async {
    final verified = afterFirstMove(91);
    await backup().writeAsString(jsonEncode(verified.toJson()));
    await pending().writeAsString(jsonEncode(afterFirstMove(27).toJson()));
    final loaded = await FileGameRepository(directory).load();
    expect(loaded.status, LoadStatus.recovered);
    expectSame(loaded.state, verified);
  });

  test('SAVE-17 malformed JSON record or invalid board restores backup', () async {
    final verified = afterFirstMove(91);
    await repository.save(verified);
    await repository.save(afterFirstMove(27));
    final tampered = afterFirstMove(27).toJson()
      ..['board'] = List<int?>.filled(64, 99);
    await primary().writeAsString(jsonEncode(tampered));
    final loaded = await FileGameRepository(directory).load();
    expect(loaded.status, LoadStatus.recovered);
    expectSame(loaded.state, verified);
  });

  test('SAVE-18 oversized primary payload is rejected before decoding', () async {
    final safe = afterFirstMove(19);
    await repository.save(safe);
    await repository.save(afterFirstMove(29));
    await primary().writeAsString(' ' * (1024 * 128));
    final recovered = await FileGameRepository(directory).load();
    expect(recovered.status, LoadStatus.recovered);
    expectSame(recovered.state, safe);
  });

  test('SAVE-19 rng and tray refill reproduce across a process restart', () async {
    final start = GameEngine.newGame(seed: 23456789);
    final a = GameEngine.applyMove(start, MoveAction(
      trayIndex: 0, row: 0, col: 0, expectedTurnId: start.turnId,
    )).state;
    await repository.save(a);
    var restored = (await FileGameRepository(directory).load()).state!;
    var uninterrupted = a;
    final beforeRng = a.rngState;
    // The first piece was consumed; placing the other two refills all 3.
    for (final slot in [1, 2]) {
      var done = false;
      for (var row = 0; row < 8 && !done; row++) {
        for (var col = 0; col < 8; col++) {
          final piece = uninterrupted.tray[slot];
          if (piece != null && GameEngine.canPlace(uninterrupted, piece, row, col)) {
            final move = MoveAction(trayIndex: slot, row: row, col: col,
                expectedTurnId: uninterrupted.turnId);
            uninterrupted = GameEngine.applyMove(uninterrupted, move).state;
            restored = GameEngine.applyMove(restored, move).state;
            done = true;
            break;
          }
        }
      }
      expect(done, isTrue);
    }
    expect(restored.rngState, isNot(beforeRng));
    expectSame(restored, uninterrupted);
    expect(restored.tray.whereType<Piece>(), hasLength(3));
  });

  test('SAVE-20 corrupt primary and future-version backup require explicit reset', () async {
    await primary().writeAsString('{broken');
    final version2 = afterFirstMove(13).toJson()..['schemaVersion'] = 2;
    await backup().writeAsString(jsonEncode(version2));
    final result = await repository.load();
    expect(result.status, LoadStatus.unsupportedVersion);
    await expectLater(repository.save(afterFirstMove(44)), throwsStateError);
    expect(jsonDecode(await backup().readAsString()), version2);
  });

  test('SAVE-12 clear existing save allows starting a fresh game', () async {
    await repository.save(afterFirstMove(93));
    await repository.clear();
    expect((await repository.load()).status, LoadStatus.empty);
    expect(await primary().exists(), isFalse);
    expect(await backup().exists(), isFalse);
  });
}
