import 'package:flutter_test/flutter_test.dart';
import 'package:block_plasma_neon_grid/domain/game_engine.dart';

GameState fixture({List<int?>? board, List<Piece?>? tray, int score = 0,
    int best = 0, int combo = 0, int seed = 7, int turn = 0}) => GameState(
  board: board ?? List<int?>.filled(64, null),
  tray: tray ?? [PieceCatalog.byId('single'), null, null],
  score: score, bestScore: best < score ? score : best,
  combo: combo, rngState: seed, turnId: turn);

MoveResult put(GameState s, {int slot = 0, int row = 0, int col = 0,
    int? turn}) => GameEngine.applyMove(s, MoveAction(trayIndex: slot,
      row: row, col: col, expectedTurnId: turn ?? s.turnId));

void main() {
  group('Canonical core invariants', () {
    test('01 — initial board and tray dimensions', () {
      final s = GameEngine.newGame(seed: 1);
      expect(s.board, hasLength(64));
      expect(s.tray, hasLength(3));
      expect(s.board.where((c) => c != null), isEmpty);
    });
    test('02 — piece catalog exactly 15 original legal shapes', () {
      expect(PieceCatalog.all, hasLength(15));
      expect(PieceCatalog.all.every((p) => p.isValid), isTrue);
      expect(PieceCatalog.all.map((p) => p.id).toSet(), hasLength(15));
    });
    test('03 — placing valid single adds 5 points and consumes slot', () {
      final r = put(fixture());
      expect(r.accepted, isTrue);
      expect(r.state.board[0], isNotNull);
      expect(r.state.tray[0], isNull);
      expect(r.scoreDelta, 5);
    });
    test('04 — duplicate / stale turn rejects without mutation', () {
      final s = fixture();
      final r = put(s, turn: -1);
      expect(r.error, MoveError.staleTurn);
      expect(identical(r.state, s), isTrue);
    });
    test('05 — occupied cell is rejected unchanged', () {
      final b = List<int?>.filled(64, null)..[0] = 1;
      final s = fixture(board: b);
      final r = put(s);
      expect(r.error, MoveError.overlap);
      expect(identical(r.state, s), isTrue);
    });
    test('06 — negative anchor is out of bounds', () {
      final s = fixture();
      final r = put(s, col: -1);
      expect(r.error, MoveError.outOfBounds);
      expect(identical(r.state, s), isTrue);
    });
    test('07 — 2x2 at bottom-right overflows', () {
      final s = fixture(tray: [PieceCatalog.byId('square2'), null, null]);
      expect(put(s, row: 7, col: 7).error, MoveError.outOfBounds);
    });
    test('08 — empty tray slot is rejected', () {
      final s = fixture();
      expect(put(s, slot: 1).error, MoveError.unavailablePiece);
    });
    test('09 — completed row clears 8 cells', () {
      final b = List<int?>.filled(64, null);
      for (var c = 0; c < 7; c++) { b[c] = 1; }
      final r = put(fixture(board: b), col: 7);
      expect(r.clearedRows, 1);
      expect(r.clearedCells, 8);
      expect(r.state.board.take(8).where((c) => c != null), isEmpty);
      expect(r.scoreDelta, 5 + 80 + 20);
    });
    test('10 — column clears independently', () {
      final b = List<int?>.filled(64, null);
      for (var r = 0; r < 7; r++) { b[r * 8] = 1; }
      final result = put(fixture(board: b), row: 7);
      expect(result.clearedColumns, 1);
      expect(result.clearedCells, 8);
    });
    test('11 — simultaneous cross counts 15 unique cells', () {
      final b = List<int?>.filled(64, null);
      for (var n = 1; n < 8; n++) { b[n] = 1; b[n * 8] = 1; }
      final r = put(fixture(board: b));
      expect(r.clearedRows, 1);
      expect(r.clearedColumns, 1);
      expect(r.clearedCells, 15);
      expect(r.scoreDelta, 5 + 150 + 25 + 20);
    });
    test('12 — clearing combo increments, no-clear resets', () {
      final b = List<int?>.filled(64, null);
      for (var n = 0; n < 7; n++) { b[n] = 1; }
      final r = put(fixture(board: b, combo: 2), col: 7);
      expect(r.state.combo, 3);
      expect(r.scoreDelta, 5 + 80 + 60);
      final n = put(fixture(combo: 3));
      expect(n.state.combo, 0);
    });
    test('13 — three empty tray slots refill on last placement', () {
      final s = fixture();
      final result = put(s);
      expect(result.state.tray.whereType<Piece>(), hasLength(3));
      expect(result.state.rngState, isNot(s.rngState));
    });
    test('14 — fully occupied board has no legal move', () {
      final s = fixture(board: List<int?>.filled(64, 1));
      expect(GameEngine.hasLegalMove(s), isFalse);
    });
    test('15 — exactly replayed input reproduces board, tray, score, RNG', () {
      final a = GameEngine.newGame(seed: 12345);
      final b = GameEngine.newGame(seed: 12345);
      expect(a.tray.map((p) => p?.id), b.tray.map((p) => p?.id));
      final x = put(a);
      final y = put(b);
      expect(x.state.board, y.state.board);
      expect(x.state.tray.map((p) => p?.id), y.state.tray.map((p) => p?.id));
      expect(x.state.rngState, y.state.rngState);
      expect(x.state.score, y.state.score);
    });
    test('16 — score and best remain monotonic', () {
      final r = put(fixture(best: 900));
      expect(r.state.bestScore, 900);
      expect(r.state.score, greaterThanOrEqualTo(0));
    });
    test('17 — snapshot roundtrips exact board, score, tray, RNG', () {
      final r = put(fixture());
      final restored = GameState.fromJson(r.state.toJson());
      expect(restored.board, r.state.board);
      expect(restored.tray.map((p) => p?.id), r.state.tray.map((p) => p?.id));
      expect(restored.rngState, r.state.rngState);
      expect(restored.turnId, r.state.turnId);
    });
    test('18 — malformed and unsupported snapshot fails safely', () {
      expect(() => GameState.fromJson({'schemaVersion': 99}), throwsFormatException);
      expect(() => GameState.fromJson({'schemaVersion': 1, 'board': []}),
          throwsFormatException);
    });
    test('19 — invalid or duplicate piece offsets rejected', () {
      expect(Piece('bad', [const CellOffset(0, 0), const CellOffset(0, 0)]).isValid, isFalse);
      expect(Piece('bad2', [const CellOffset(4, 0)]).isValid, isFalse);
    });
    test('20 — no available piece implies game over after legal move', () {
      final b = List<int?>.filled(64, 1)..[0] = null;
      for (var n = 1; n < 7; n++) { b[n * 8 + n] = null; }
      b[7] = null;
      b[56] = null;
      final s = fixture(board: b, tray: [PieceCatalog.byId('single'),
          PieceCatalog.byId('square2'), null]);
      final result = put(s);
      expect(result.accepted, isTrue);
      expect(result.state.gameOver, isTrue);
    });
  });
}
