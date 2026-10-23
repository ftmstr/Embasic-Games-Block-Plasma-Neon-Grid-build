import 'package:block_plasma_neon_grid/data/game_repository.dart';
import 'package:block_plasma_neon_grid/domain/game_engine.dart';
import 'package:block_plasma_neon_grid/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryGameRepository implements GameRepository {
  _MemoryGameRepository(this.initial);
  final GameState initial;
  final saved = <GameState>[];
  @override
  Future<LoadResult> load() async => LoadResult(LoadStatus.loaded, initial);
  @override
  Future<void> save(GameState snapshot) async => saved.add(snapshot);
  @override
  Future<void> clear() async {}
}

GameState _fixture({bool over = false, bool lastSlot = false}) => GameState(
  board: over
      ? List<int?>.filled(64, 1)
      : (List<int?>.filled(64, null)..[0] = 1),
  tray: lastSlot
      ? [PieceCatalog.byId('single'), null, null]
      : [PieceCatalog.byId('single'),
          PieceCatalog.byId('double_h'), PieceCatalog.byId('triple_v')],
  score: 73,
  bestScore: 100,
  combo: 0,
  rngState: 314159265,
  turnId: 9,
  gameOver: over,
);

void _screen(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _buildClassic(WidgetTester tester,
    _MemoryGameRepository repository, {double scale = 1}) async {
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: MaterialApp(home: ClassicScreen(repository: repository)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final dims in <(double, double)>[
    (320, 640), (360, 800), (393, 873), (412, 915), (600, 960),
  ]) {
    testWidgets('UI-QA responsive Classic ${dims.$1}x${dims.$2} no overflow',
        (tester) async {
      _screen(tester, dims.$1, dims.$2);
      await _buildClassic(tester, _MemoryGameRepository(_fixture()));
      expect(tester.takeException(), isNull);
      expect(find.byType(DragTarget<int>), findsNWidgets(64));
      expect(find.byType(LongPressDraggable<int>), findsNWidgets(3));
      final board = tester.getSize(find.byType(GridView));
      expect(board.width, lessThanOrEqualTo(dims.$1 - 30));
      expect(board.height, closeTo(board.width, 0.1));
    });
  }

  for (final scale in [1.3, 2.0]) {
    testWidgets('UI-QA text scaling ${scale}x on 320x640 scrolls without overflow',
        (tester) async {
      _screen(tester, 320, 640);
      await _buildClassic(tester, _MemoryGameRepository(_fixture()), scale: scale);
      expect(tester.takeException(), isNull);
      expect(find.text('SCORE 73'), findsOneWidget);
      expect(find.byType(DragTarget<int>), findsNWidgets(64));
      expect(find.byType(LongPressDraggable<int>), findsNWidgets(3));
    });
    testWidgets('UI-QA Home at ${scale}x and 320x640 has accessible PLAY CTA',
        (tester) async {
      _screen(tester, 320, 640);
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: const MaterialApp(home: HomeScreen()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('PLAY'), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(FilledButton, 'PLAY')).height,
          greaterThanOrEqualTo(48));
    });
  }

  testWidgets('UI-QA rapid repeated pause does not stack dialogs', (tester) async {
    await _buildClassic(tester, _MemoryGameRepository(_fixture()));
    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    expect(find.text('PAUSED'), findsNothing);
  });

  testWidgets('UI-QA restart is confirmed; cancel keeps score and turn', (tester) async {
    final repo = _MemoryGameRepository(_fixture());
    await _buildClassic(tester, repo);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESTART'));
    await tester.pumpAndSettle();
    expect(find.text('CONFIRM RESTART'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(find.text('SCORE 73'), findsOneWidget);
    // Pause deliberately persists a verified snapshot. Cancelling restart
    // must not alter the saved gameplay turn or score.
    expect(repo.saved, isNotEmpty);
    expect(repo.saved.every((s) => s.turnId == 9 && s.score == 73), isTrue);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESTART'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESTART GAME'));
    await tester.pumpAndSettle();
    expect(find.text('SCORE 0'), findsOneWidget);
    expect(find.text('BEST 100'), findsOneWidget);
    expect(repo.saved.last.score, 0);
    expect(repo.saved.last.bestScore, 100);
  });

  testWidgets('UI-QA game-over exposes retry and home without overlay overflow',
      (tester) async {
    _screen(tester, 320, 640);
    final repo = _MemoryGameRepository(_fixture(over: true));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(repository: repo)));
    await tester.tap(find.text('PLAY'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('PLASMA OVERLOAD'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
    expect(find.text('PLAY'), findsOneWidget);
  });

  testWidgets('UI-QA invalid occupied drop leaves state and disk untouched',
      (tester) async {
    final repo = _MemoryGameRepository(_fixture());
    await _buildClassic(tester, repo);
    final finger = await tester.startGesture(
        tester.getCenter(find.byType(LongPressDraggable<int>).first));
    await tester.pump(const Duration(milliseconds: 850));
    await finger.moveTo(tester.getCenter(find.byType(DragTarget<int>).first));
    await tester.pump(const Duration(milliseconds: 200));
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('SCORE 73'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('UI-QA valid long-press drag commits exactly one turn',
      (tester) async {
    _screen(tester, 393, 873);
    final repo = _MemoryGameRepository(_fixture());
    await _buildClassic(tester, repo);
    final finger = await tester.startGesture(
        tester.getCenter(find.byType(LongPressDraggable<int>).first));
    await tester.pump(const Duration(milliseconds: 850));
    await finger.moveTo(tester.getCenter(find.byType(DragTarget<int>).last));
    await tester.pump(const Duration(milliseconds: 200));
    await finger.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('SCORE 78'), findsOneWidget);
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.turnId, 10);
    expect(repo.saved.single.board[63], 1);
  });


  testWidgets('UI-QA Android swipe without long-press commits one legal move',
      (tester) async {
    _screen(tester, 393, 873);
    final repo = _MemoryGameRepository(_fixture());
    await _buildClassic(tester, repo);
    final finger = await tester.startGesture(
        tester.getCenter(find.byType(LongPressDraggable<int>).first));
    // This intentionally moves before the recognizer's long-press deadline:
    // the raw-pointer recovery must not depend on onDragStarted/onDragEnd.
    await tester.pump(const Duration(milliseconds: 50));
    await finger.moveTo(tester.getCenter(find.byType(DragTarget<int>).last));
    await tester.pump(const Duration(milliseconds: 50));
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('SCORE 78'), findsOneWidget);
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.turnId, 10);
    expect(repo.saved.single.board[63], 1);
  });

  testWidgets('UI-QA raw pointer fallback rejects outside-board release',
      (tester) async {
    _screen(tester, 393, 873);
    final repo = _MemoryGameRepository(_fixture());
    await _buildClassic(tester, repo);
    final finger = await tester.startGesture(
        tester.getCenter(find.byType(LongPressDraggable<int>).first));
    await tester.pump(const Duration(milliseconds: 40));
    await finger.moveTo(const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 40));
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('SCORE 73'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('UI-QA drag cannot double commit after 3-slot refill',
      (tester) async {
    _screen(tester, 393, 873);
    final repo = _MemoryGameRepository(_fixture(lastSlot: true));
    await _buildClassic(tester, repo);
    final finger = await tester.startGesture(
        tester.getCenter(find.byType(LongPressDraggable<int>).first));
    await tester.pump(const Duration(milliseconds: 850));
    await finger.moveTo(tester.getCenter(find.byType(DragTarget<int>).last));
    await tester.pump(const Duration(milliseconds: 200));
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text('SCORE 78'), findsOneWidget);
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.turnId, 10);
    expect(repo.saved.single.board[63], 1);
    expect(repo.saved.single.tray.whereType<Piece>(), hasLength(3));
  });

  testWidgets('UI-QA selecting a tray slot then tapping a legal cell commits',
      (tester) async {
    final repo = _MemoryGameRepository(_fixture());
    await _buildClassic(tester, repo);
    await tester.tap(find.byKey(const ValueKey('tray-select-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('board-tap-63')));
    await tester.pumpAndSettle();
    expect(repo.saved.last.score, 78);
    expect(repo.saved.last.turnId, 10);
    expect(find.text('SCORE 78'), findsOneWidget);
  });

  testWidgets('UI-QA drag preview is above pointer by 44dp', (tester) async {
    await _buildClassic(tester, _MemoryGameRepository(_fixture()));
    final drag = tester.widget<LongPressDraggable<int>>(
        find.byType(LongPressDraggable<int>).first);
    expect(drag.feedback, isA<Transform>());
    expect(drag.dragAnchorStrategy, same(pointerDragAnchorStrategy));
    expect(drag.feedbackOffset, Offset.zero);
    final transform = drag.feedback as Transform;
    final point = MatrixUtils.transformPoint(transform.transform, Offset.zero);
    expect(point.dy, -44);
  });
}
