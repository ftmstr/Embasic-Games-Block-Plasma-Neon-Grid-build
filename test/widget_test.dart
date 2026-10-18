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

  @override
  Future<LoadResult> load() async => loaded;

  @override
  Future<void> save(GameState state) async {
    saved.add(state);
  }

  @override
  Future<void> clear() async {
    cleared = true;
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
