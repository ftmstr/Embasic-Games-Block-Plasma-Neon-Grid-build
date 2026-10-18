import 'package:flutter/material.dart';
import 'domain/game_engine.dart';
import 'design/tokens.dart';

void main() => runApp(const BlockPlasmaApp());

class BlockPlasmaApp extends StatelessWidget {
  const BlockPlasmaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Block Plasma: Neon Grid',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true,
          scaffoldBackgroundColor: PlasmaColors.background,
          colorSchemeSeed: PlasmaColors.cyan),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('EMBASIC GAMES', style: TextStyle(
                    letterSpacing: 5, color: PlasmaColors.secondary, fontSize: 13)),
                const SizedBox(height: 24),
                const Icon(Icons.grid_view_rounded, color: PlasmaColors.cyan, size: 88),
                const SizedBox(height: 24),
                const Text('BLOCK PLASMA', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900,
                      letterSpacing: 2, color: PlasmaColors.text)),
                const Text('NEON GRID', style: TextStyle(fontSize: 23,
                    letterSpacing: 5, color: PlasmaColors.cyan)),
                const SizedBox(height: 48),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const ClassicScreen())),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('PLAY'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => showDialog<void>(context: context,
                    builder: (_) => const AlertDialog(title: Text('HOW TO PLAY'),
                      content: Text('Drag a piece from the tray onto empty cells. '
                          'Complete a row or column to clear it.'))),
                  child: const Text('HOW TO PLAY'),
                ),
                const SizedBox(height: 20),
                const Text('Offline Classic • Early development build',
                    style: TextStyle(color: PlasmaColors.secondary)),
              ]),
            ),
          ),
        ),
      );
}

class ClassicScreen extends StatefulWidget {
  const ClassicScreen({super.key});

  @override
  State<ClassicScreen> createState() => _ClassicScreenState();
}

class _ClassicScreenState extends State<ClassicScreen> {
  late GameState state = GameEngine.newGame(seed: DateTime.now().microsecondsSinceEpoch);

  void place(int slot, int row, int col) {
    final result = GameEngine.applyMove(state, MoveAction(
        trayIndex: slot, row: row, col: col, expectedTurnId: state.turnId));
    if (result.accepted) {
      setState(() => state = result.state);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 500),
        content: Text('Cannot place piece: ${result.error.name}')));
    }
  }

  void restart() => setState(() => state = GameEngine.newGame(
      seed: DateTime.now().microsecondsSinceEpoch, bestScore: state.bestScore));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('CLASSIC'),
          backgroundColor: PlasmaColors.background,
          actions: [IconButton(icon: const Icon(Icons.pause),
            tooltip: 'Pause', onPressed: () => showDialog<void>(
              context: context, builder: (dialogContext) => AlertDialog(
                title: const Text('PAUSED'), actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('CONTINUE')),
                  TextButton(onPressed: () {
                    Navigator.pop(dialogContext);
                    restart();
                  }, child: const Text('RESTART')),
                ])))],
        ),
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final boardSize = (constraints.maxWidth - 24).clamp(0.0,
              constraints.maxHeight - 220 > 0 ? constraints.maxHeight - 220 : 0.0).toDouble();
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('BEST ${state.bestScore}',
                    style: const TextStyle(color: PlasmaColors.secondary)),
                  Text('SCORE ${state.score}', style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: PlasmaColors.cyan))])),
            const SizedBox(height: 12),
            SizedBox(width: boardSize, height: boardSize,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8),
                itemCount: 64,
                itemBuilder: (context, index) {
                  final row = index ~/ 8;
                  final col = index % 8;
                  return DragTarget<int>(
                    onWillAcceptWithDetails: (_) => !state.gameOver,
                    onAcceptWithDetails: (details) => place(details.data, row, col),
                    builder: (context, candidateData, rejectedData) {
                      final targetPiece = candidateData.isEmpty ? null : state.tray[candidateData.first];
                      final legal = targetPiece != null && GameEngine.canPlace(state, targetPiece, row, col);
                      final colorIndex = state.board[index];
                      final base = colorIndex == null ? PlasmaColors.empty : PlasmaColors.block(colorIndex);
                      return Container(
                        margin: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: candidateData.isNotEmpty
                              ? (legal ? PlasmaColors.lime.withValues(alpha: 0.45)
                                       : PlasmaColors.warning.withValues(alpha: 0.35))
                              : base,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: candidateData.isNotEmpty
                            ? (legal ? PlasmaColors.lime : PlasmaColors.warning)
                            : PlasmaColors.gridStroke, width: 1),
                          boxShadow: colorIndex == null ? null : [BoxShadow(
                            color: base.withValues(alpha: 0.25), blurRadius: 6)],
                        ),
                      );
                    });
                },
              )),
            const SizedBox(height: 18),
            Text('DRAG A PIECE TO THE GRID', style: TextStyle(
              color: PlasmaColors.secondary.withValues(alpha: 0.9), fontSize: 11)),
            const SizedBox(height: 10),
            SizedBox(height: 82, child: Row(
              children: List.generate(3, (index) {
                final piece = state.tray[index];
                return Expanded(child: Center(
                  child: piece == null ? const SizedBox(width: 64, height: 64) :
                  LongPressDraggable<int>(
                    data: index,
                    feedback: Material(color: Colors.transparent,
                      child: _PiecePreview(piece: piece, size: 18)),
                    childWhenDragging: Opacity(opacity: 0.2,
                      child: _PiecePreview(piece: piece, size: 14)),
                    child: _PiecePreview(piece: piece, size: 14),
                  ),
                ));
              }),
            )),
            if (state.combo > 0) Text('COMBO × ${state.combo}',
              style: const TextStyle(color: PlasmaColors.lime)),
            if (state.gameOver) Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                const Text('PLASMA OVERLOAD', style: TextStyle(
                    color: PlasmaColors.warning, fontWeight: FontWeight.bold)),
                FilledButton(onPressed: restart, child: const Text('RETRY')),
              ])),
          ]));
        })),
      );
}

class _PiecePreview extends StatelessWidget {
  const _PiecePreview({required this.piece, required this.size});
  final Piece piece;
  final double size;

  @override
  Widget build(BuildContext context) {
    final width = piece.offsets.map((p) => p.x).reduce((a, b) => a > b ? a : b) + 1;
    final height = piece.offsets.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 1;
    return SizedBox(width: width * size, height: height * size,
      child: Stack(children: piece.offsets.map((offset) => Positioned(
        left: offset.x * size, top: offset.y * size,
        width: size - 1, height: size - 1,
        child: DecoratedBox(decoration: BoxDecoration(
          color: PlasmaColors.cyan, borderRadius: BorderRadius.circular(3),
          border: Border.all(color: PlasmaColors.text.withValues(alpha: 0.7)),
          boxShadow: const [BoxShadow(color: PlasmaColors.blue, blurRadius: 4)]))))
          .toList()));
  }
}
