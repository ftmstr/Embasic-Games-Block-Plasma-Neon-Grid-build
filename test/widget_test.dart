import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_plasma_neon_grid/main.dart';
import 'package:block_plasma_neon_grid/data/game_repository.dart';
import 'package:block_plasma_neon_grid/domain/game_engine.dart';


class _FakeRepository implements GameRepository {
  _FakeRepository(this.loaded);
  LoadResult loaded;
  final saved = <GameState>[];
  bool cleared = false;
  bool failClear = false;

  @override
  Future<LoadResult> load() async => loaded;

  @override
  Future<void> save(GameState state) async {
    saved.add(state);
  }

  @override
  Future<void> clear() async {
    cleared = true;
    if (failClear) throw FileSystemException('denied');
  }
}

void main() {
  testWidgets('Saved Classic session restores score and 64-cell board',
      (tester) async {
    final prior = GameEngine.newGame(seed: 4);
    final next = GameEngine.applyMove(prior, MoveAction(
      trayIndex: 0, row: 0, col: 0, expectedTurnId: prior.turnId,
    )).state;
    final fake = _FakeRepository(LoadResult(LoadStatus.loaded, next));
    await tester.pumpWidget(MaterialApp(home: ClassicScreen(repository: fake)));
    await tester.pumpAndSettle();
    expect(find.text('SCORE ${next.score}'), findsOneWidget);
    expect(find.byType(DragTarget<int>), findsNWidgets(64));
  });

  testWidgets('Unsupported schema requires explicit start-new-game action',
      (tester) async {
    final fake = _FakeRepository(const LoadResult(LoadStatus.unsupportedVersion));
    await tester.pumpWidget(MaterialApp(home: ClassicScreen(repository: fake)));
    await tester.pumpAndSettle();
    expect(find.text('START NEW GAME'), findsOneWidget);
    expect(fake.saved, isEmpty);
    await tester.tap(find.text('START NEW GAME'));
    await tester.pumpAndSettle();
    expect(fake.cleared, isTrue);
    expect(fake.saved, hasLength(1));
    expect(find.byType(DragTarget<int>), findsNWidgets(64));
  });

  testWidgets('Failed clear of newer save does not unlock gameplay or overwrite',
      (tester) async {
    final fake = _FakeRepository(const LoadResult(LoadStatus.unsupportedVersion))
      ..failClear = true;
    await tester.pumpWidget(MaterialApp(home: ClassicScreen(repository: fake)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('START NEW GAME'));
    await tester.pumpAndSettle();
    expect(fake.cleared, isTrue);
    expect(fake.saved, isEmpty);
    expect(find.byType(DragTarget<int>), findsNothing);
    expect(find.text('START NEW GAME'), findsOneWidget);
  });

  testWidgets('Lifecycle pause persists current loaded turn', (tester) async {
    final before = GameEngine.newGame(seed: 52);
    final saved = GameEngine.applyMove(before, MoveAction(
      trayIndex: 0, row: 0, col: 0, expectedTurnId: before.turnId,
    )).state;
    final fake = _FakeRepository(LoadResult(LoadStatus.loaded, saved));
    await tester.pumpWidget(MaterialApp(home: ClassicScreen(repository: fake)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(fake.saved, isNotEmpty);
    expect(fake.saved.last.toJson(), saved.toJson());
  });

  testWidgets('Real long-press drag into last grid cell saves exact next turn',
      (tester) async {
    final board = List<int?>.filled(64, null)..[0] = 1;
    final before = GameState(
      board: board,
      tray: [
        PieceCatalog.byId('single'),
        PieceCatalog.byId('double_h'),
        PieceCatalog.byId('triple_v'),
      ],
      score: 73,
      bestScore: 100,
      combo: 0,
      rngState: 314159265,
      turnId: 9,
    );
    final fake = _FakeRepository(LoadResult(LoadStatus.loaded, before));
    await tester.pumpWidget(MaterialApp(
        home: ClassicScreen(repository: fake)));
    await tester.pumpAndSettle();

    final origin = find.byType(LongPressDraggable<int>).first;
    final destination = find.byType(DragTarget<int>).at(63);
    final finger = await tester.startGesture(tester.getCenter(origin));
    await tester.pump(const Duration(milliseconds: 850));
    await finger.moveTo(tester.getCenter(destination));
    await tester.pump(const Duration(milliseconds: 200));
    await finger.up();
    await tester.pumpAndSettle();

    expect(fake.saved, isNotEmpty);
    final after = fake.saved.last;
    expect(after.score, 78);
    expect(after.board[0], 1);
    expect(after.board[63], 1);
    expect(after.tray[0], isNull);
    expect(after.turnId, 10);
    expect(after.rngState, 314159265);
    expect(after.bestScore, 100);
    expect(find.text('SCORE 78'), findsOneWidget);
  });

  testWidgets('Home opens classic 8 by 8 grid and three pieces', (tester) async {
    await tester.pumpWidget(BlockPlasmaApp(
      repository: _FakeRepository(const LoadResult(LoadStatus.empty)),
    ));
    expect(find.text('BLOCK PLASMA'), findsOneWidget);
    await tester.tap(find.text('PLAY'));
    await tester.pumpAndSettle();
    expect(find.byType(DragTarget<int>), findsNWidgets(64));
    expect(find.byType(LongPressDraggable<int>), findsNWidgets(3));
    expect(find.textContaining('SCORE'), findsOneWidget);
  });
}
