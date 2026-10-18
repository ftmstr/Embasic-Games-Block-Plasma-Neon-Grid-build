/// Deterministic Block Plasma core. Pure Dart: no Flutter or persistence imports.
library;

class CellOffset {
  const CellOffset(this.x, this.y);
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is CellOffset && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class Piece {
  Piece(this.id, List<CellOffset> offsets)
      : offsets = List<CellOffset>.unmodifiable(offsets);
  final String id;
  final List<CellOffset> offsets;

  bool get isValid {
    if (offsets.isEmpty || offsets.toSet().length != offsets.length) {
      return false;
    }
    final minX = offsets.map((e) => e.x).reduce((a, b) => a < b ? a : b);
    final minY = offsets.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    return minX == 0 && minY == 0 &&
        offsets.every((o) => o.x >= 0 && o.y >= 0 && o.x < 8 && o.y < 8);
  }
}

class PieceCatalog {
  static final List<Piece> all = List<Piece>.unmodifiable([
    Piece('single', [const CellOffset(0, 0)]),
    Piece('double_h', [const CellOffset(0, 0), const CellOffset(1, 0)]),
    Piece('double_v', [const CellOffset(0, 0), const CellOffset(0, 1)]),
    Piece('triple_h', [const CellOffset(0, 0), const CellOffset(1, 0), const CellOffset(2, 0)]),
    Piece('triple_v', [const CellOffset(0, 0), const CellOffset(0, 1), const CellOffset(0, 2)]),
    Piece('square2', [const CellOffset(0, 0), const CellOffset(1, 0), const CellOffset(0, 1), const CellOffset(1, 1)]),
    Piece('l3', [const CellOffset(0, 0), const CellOffset(0, 1), const CellOffset(1, 1)]),
    Piece('j3', [const CellOffset(1, 0), const CellOffset(1, 1), const CellOffset(0, 1)]),
    Piece('t4', [const CellOffset(0, 0), const CellOffset(1, 0), const CellOffset(2, 0), const CellOffset(1, 1)]),
    Piece('s4', [const CellOffset(1, 0), const CellOffset(2, 0), const CellOffset(0, 1), const CellOffset(1, 1)]),
    Piece('z4', [const CellOffset(0, 0), const CellOffset(1, 0), const CellOffset(1, 1), const CellOffset(2, 1)]),
    Piece('l4', [const CellOffset(0, 0), const CellOffset(0, 1), const CellOffset(0, 2), const CellOffset(1, 2)]),
    Piece('long4_h', [const CellOffset(0, 0), const CellOffset(1, 0), const CellOffset(2, 0), const CellOffset(3, 0)]),
    Piece('long4_v', [const CellOffset(0, 0), const CellOffset(0, 1), const CellOffset(0, 2), const CellOffset(0, 3)]),
    Piece('rectangle2x3', [const CellOffset(0, 0), const CellOffset(1, 0), const CellOffset(2, 0), const CellOffset(0, 1), const CellOffset(1, 1), const CellOffset(2, 1)]),
  ]);

  static Piece byId(String id) => all.firstWhere((p) => p.id == id);
}

class GameState {
  GameState({
    required List<int?> board,
    required List<Piece?> tray,
    required this.score,
    required this.bestScore,
    required this.combo,
    required this.rngState,
    required this.turnId,
    this.gameOver = false,
  })  : board = List<int?>.unmodifiable(board),
        tray = List<Piece?>.unmodifiable(tray) {
    if (board.length != 64 || tray.length != 3 || score < 0 ||
        bestScore < score || combo < 0 || turnId < 0 ||
        tray.any((p) => p != null && !p.isValid)) {
      throw ArgumentError('Invalid game snapshot');
    }
  }

  static const int schemaVersion = 1;
  final List<int?> board;
  final List<Piece?> tray;
  final int score;
  final int bestScore;
  final int combo;
  final int rngState;
  final int turnId;
  final bool gameOver;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'board': board,
        'tray': tray.map((p) => p?.id).toList(),
        'score': score,
        'bestScore': bestScore,
        'combo': combo,
        'rngState': rngState,
        'turnId': turnId,
        'gameOver': gameOver,
      };

  static GameState fromJson(Map<String, dynamic> data) {
    if (data['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported save version');
    }
    try {
      final board = (data['board'] as List<dynamic>).map((e) => e as int?).toList();
      final tray = (data['tray'] as List<dynamic>)
          .map((id) => id == null ? null : PieceCatalog.byId(id as String))
          .toList();
      return GameState(
        board: board, tray: tray,
        score: data['score'] as int,
        bestScore: data['bestScore'] as int,
        combo: data['combo'] as int,
        rngState: data['rngState'] as int,
        turnId: data['turnId'] as int,
        gameOver: data['gameOver'] as bool,
      );
    } catch (_) {
      throw const FormatException('Invalid save data');
    }
  }
}

class MoveAction {
  const MoveAction({required this.trayIndex, required this.row,
    required this.col, required this.expectedTurnId});
  final int trayIndex;
  final int row;
  final int col;
  final int expectedTurnId;
}

enum MoveError { none, staleTurn, unavailablePiece, invalidPiece, outOfBounds, overlap, gameOver }

class MoveResult {
  const MoveResult({required this.state, required this.accepted,
    required this.error, this.scoreDelta = 0,
    this.clearedRows = 0, this.clearedColumns = 0,
    this.clearedCells = 0});
  final GameState state;
  final bool accepted;
  final MoveError error;
  final int scoreDelta;
  final int clearedRows;
  final int clearedColumns;
  final int clearedCells;
}

class _Rng {
  _Rng(this.state);
  int state;
  int nextInt(int bound) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return state % bound;
  }
}

class GameEngine {
  static GameState newGame({int seed = 1, int bestScore = 0}) {
    final rng = _Rng(seed & 0xFFFFFFFF);
    final tray = List<Piece?>.generate(3, (_) => PieceCatalog.all[rng.nextInt(PieceCatalog.all.length)]);
    return GameState(board: List<int?>.filled(64, null), tray: tray,
        score: 0, bestScore: bestScore, combo: 0,
        rngState: rng.state, turnId: 0);
  }

  static bool canPlace(GameState state, Piece piece, int row, int col) {
    if (!piece.isValid) return false;
    for (final offset in piece.offsets) {
      final x = col + offset.x;
      final y = row + offset.y;
      if (x < 0 || x >= 8 || y < 0 || y >= 8 || state.board[y * 8 + x] != null) {
        return false;
      }
    }
    return true;
  }

  static bool hasLegalMove(GameState state) {
    for (final piece in state.tray) {
      if (piece == null) continue;
      for (var row = 0; row < 8; row++) {
        for (var col = 0; col < 8; col++) {
          if (canPlace(state, piece, row, col)) return true;
        }
      }
    }
    return false;
  }

  static MoveResult applyMove(GameState state, MoveAction action) {
    MoveResult reject(MoveError error) => MoveResult(
        state: state, accepted: false, error: error);
    if (action.expectedTurnId != state.turnId) return reject(MoveError.staleTurn);
    if (state.gameOver) return reject(MoveError.gameOver);
    if (action.trayIndex < 0 || action.trayIndex >= 3 || state.tray[action.trayIndex] == null) {
      return reject(MoveError.unavailablePiece);
    }
    final piece = state.tray[action.trayIndex]!;
    if (!piece.isValid) return reject(MoveError.invalidPiece);
    if (piece.offsets.any((e) => action.col + e.x < 0 || action.col + e.x >= 8 ||
        action.row + e.y < 0 || action.row + e.y >= 8)) {
      return reject(MoveError.outOfBounds);
    }
    if (!canPlace(state, piece, action.row, action.col)) return reject(MoveError.overlap);

    final board = List<int?>.of(state.board);
    final color = (PieceCatalog.all.indexWhere((p) => p.id == piece.id) % 5) + 1;
    for (final offset in piece.offsets) {
      board[(action.row + offset.y) * 8 + action.col + offset.x] = color;
    }
    final rows = <int>[];
    final columns = <int>[];
    for (var n = 0; n < 8; n++) {
      if (List.generate(8, (col) => board[n * 8 + col]).every((c) => c != null)) rows.add(n);
      if (List.generate(8, (row) => board[row * 8 + n]).every((c) => c != null)) columns.add(n);
    }
    final clear = <int>{};
    for (final row in rows) {
      for (var col = 0; col < 8; col++) { clear.add(row * 8 + col); }
    }
    for (final col in columns) {
      for (var row = 0; row < 8; row++) { clear.add(row * 8 + col); }
    }
    for (final index in clear) { board[index] = null; }
    final lines = rows.length + columns.length;
    final combo = clear.isEmpty ? 0 : state.combo + 1;
    final delta = piece.offsets.length * 5 + clear.length * 10 +
        (lines > 1 ? (lines - 1) * 25 : 0) + (clear.isEmpty ? 0 : combo * 20);
    final tray = List<Piece?>.of(state.tray);
    tray[action.trayIndex] = null;
    final rng = _Rng(state.rngState);
    if (tray.every((p) => p == null)) {
      for (var i = 0; i < 3; i++) {
        tray[i] = PieceCatalog.all[rng.nextInt(PieceCatalog.all.length)];
      }
    }
    final score = state.score + delta;
    var next = GameState(board: board, tray: tray, score: score,
        bestScore: score > state.bestScore ? score : state.bestScore,
        combo: combo, rngState: rng.state, turnId: state.turnId + 1);
    if (!hasLegalMove(next)) {
      next = GameState(board: board, tray: tray, score: score,
          bestScore: next.bestScore, combo: combo, rngState: rng.state,
          turnId: next.turnId, gameOver: true);
    }
    return MoveResult(state: next, accepted: true, error: MoveError.none,
        scoreDelta: delta, clearedRows: rows.length,
        clearedColumns: columns.length, clearedCells: clear.length);
  }
}
