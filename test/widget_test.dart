import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_plasma_neon_grid/main.dart';

void main() {
  testWidgets('Home opens classic 8 by 8 grid and three pieces', (tester) async {
    await tester.pumpWidget(const BlockPlasmaApp());
    expect(find.text('BLOCK PLASMA'), findsOneWidget);
    await tester.tap(find.text('PLAY'));
    await tester.pumpAndSettle();
    expect(find.byType(DragTarget<int>), findsNWidgets(64));
    expect(find.byType(LongPressDraggable<int>), findsNWidgets(3));
    expect(find.textContaining('SCORE'), findsOneWidget);
  });
}
