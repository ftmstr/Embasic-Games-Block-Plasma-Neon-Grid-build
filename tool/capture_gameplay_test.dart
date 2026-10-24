// Actual Flutter-rendered gameplay captures. Never substitute synthetic art.
// The populated board is produced exclusively by GameEngine.applyMove.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_plasma_neon_grid/main.dart';
import 'package:block_plasma_neon_grid/domain/game_engine.dart';
import 'package:block_plasma_neon_grid/data/game_repository.dart';

class _LoadedFixture implements GameRepository {
  _LoadedFixture(this.snapshot);
  final GameState? snapshot;
  @override
  Future<LoadResult> load() async => snapshot == null
      ? const LoadResult(LoadStatus.empty)
      : LoadResult(LoadStatus.loaded, snapshot);
  @override
  Future<void> save(GameState state) async {}
  @override
  Future<void> clear() async {}
}

GameState _actualMoves(int count) {
  var state = GameEngine.newGame(seed: 314159);
  for (var turn = 0; turn < count && !state.gameOver; turn++) {
    MoveResult? accepted;
    for (var slotOffset = 0; slotOffset < 3 && accepted == null; slotOffset++) {
      final slot = (turn + slotOffset) % 3;
      final piece = state.tray[slot];
      if (piece == null) continue;
      for (var step = 0; step < 64; step++) {
        final anchor = (turn * 13 + step) % 64;
        final row = anchor ~/ 8;
        final col = anchor % 8;
        if (!GameEngine.canPlace(state, piece, row, col)) continue;
        final move = GameEngine.applyMove(state, MoveAction(
          trayIndex: slot, row: row, col: col,
          expectedTurnId: state.turnId,
        ));
        if (move.accepted) {
          accepted = move;
          break;
        }
      }
    }
    if (accepted == null) break;
    state = accepted.state;
  }
  assert(state.turnId > 0);
  return state;
}

void _portrait(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 873);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const _captureKey = ValueKey<String>('real-flutter-frame');

void main() {
  testWidgets('Capture actual Flutter Home UI', (tester) async {
    _portrait(tester);
    await tester.pumpWidget(RepaintBoundary(
      key: _captureKey,
      child: BlockPlasmaApp(repository: _LoadedFixture(null)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('PLAY'), findsOneWidget);
    await expectLater(find.byKey(_captureKey),
        matchesGoldenFile('goldens/01-home-flutter.png'));
  });

  testWidgets('Capture actual navigated gameplay with empty board', (tester) async {
    _portrait(tester);
    await tester.pumpWidget(RepaintBoundary(
      key: _captureKey,
      child: BlockPlasmaApp(repository: _LoadedFixture(null)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PLAY'));
    await tester.pumpAndSettle();
    expect(find.byType(DragTarget<int>), findsNWidgets(64));
    expect(find.byType(LongPressDraggable<int>), findsNWidgets(3));
    await expectLater(find.byKey(_captureKey),
        matchesGoldenFile('goldens/02-gameplay-start-flutter.png'));
  });

  testWidgets('Capture gameplay after real GameEngine moves', (tester) async {
    _portrait(tester);
    final snapshot = _actualMoves(11);
    expect(snapshot.turnId, greaterThan(0));
    await tester.pumpWidget(RepaintBoundary(
      key: _captureKey,
      child: BlockPlasmaApp(repository: _LoadedFixture(snapshot)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PLAY'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SCORE'), findsOneWidget);
    expect(find.byType(DragTarget<int>), findsNWidgets(64));
    await expectLater(find.byKey(_captureKey),
        matchesGoldenFile('goldens/03-gameplay-11-moves-flutter.png'));
  });

  testWidgets('Capture actual Pause overlay above played board', (tester) async {
    _portrait(tester);
    final snapshot = _actualMoves(7);
    await tester.pumpWidget(RepaintBoundary(
      key: _captureKey,
      child: BlockPlasmaApp(repository: _LoadedFixture(snapshot)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PLAY'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('PAUSED'), findsOneWidget);
    await expectLater(find.byKey(_captureKey),
        matchesGoldenFile('goldens/04-pause-flutter.png'));
  });
}
