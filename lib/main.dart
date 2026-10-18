import 'dart:async';

import 'package:flutter/material.dart';
import 'data/game_repository.dart';
import 'data/game_storage.dart';
import 'domain/game_engine.dart';
import 'design/tokens.dart';

void main() => runApp(const BlockPlasmaApp());

class BlockPlasmaApp extends StatelessWidget {
  const BlockPlasmaApp({super.key, this.repository});

  final GameRepository? repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Block Plasma: Neon Grid',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true,
          scaffoldBackgroundColor: PlasmaColors.background,
          colorSchemeSeed: PlasmaColors.cyan),
        home: HomeScreen(repository: repository),
      );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.repository});

  final GameRepository? repository;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
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
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ClassicScreen(repository: repository))),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('PLAY'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(150, 48)),
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
        ),
      );
}

class ClassicScreen extends StatefulWidget {
  const ClassicScreen({super.key, this.repository});

  /// Optional injected seam for deterministic widget and integration tests.
  final GameRepository? repository;

  @override
  State<ClassicScreen> createState() => _ClassicScreenState();
}

class _ClassicScreenState extends State<ClassicScreen>
    with WidgetsBindingObserver {
  late GameState state = GameEngine.newGame(seed: DateTime.now().microsecondsSinceEpoch);
  GameRepository? _repository;
  bool _loading = true;
  bool _needsReset = false;
  bool _pauseOpen = false;
  int? _selectedSlot;
  final Map<int, Offset> _trayTouches = {};
  String? _storageNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  Future<void> _restore() async {
    GameRepository? repository;
    LoadResult result;
    try {
      repository = widget.repository ?? await AppGameStorage.open();
      result = repository == null
          ? const LoadResult(LoadStatus.unavailable)
          : await repository.load();
    } catch (_) {
      result = const LoadResult(LoadStatus.unavailable);
    }
    if (!mounted) return;
    setState(() {
      _repository = repository;
      if (result.state != null) state = result.state!;
      _needsReset = result.status == LoadStatus.unsupportedVersion ||
          result.status == LoadStatus.corrupt;
      _storageNotice = switch (result.status) {
        LoadStatus.recovered => 'Previous game recovered from backup',
        LoadStatus.corrupt => 'Saved game is damaged; start a new game',
        LoadStatus.unsupportedVersion => 'Saved game belongs to a newer version',
        LoadStatus.unavailable => 'Local save unavailable; progress may not persist',
        _ => null,
      };
      _loading = false;
    });
    // Persist the initially created tray too: force-stop before the first
    // move should not cause a different seeded tray on the next launch.
    if (result.status == LoadStatus.empty) _saveCommittedSnapshot();
  }

  void _saveCommittedSnapshot() {
    final repository = _repository;
    if (repository == null || _needsReset) return;
    // FileGameRepository queues writes, so concurrent drags cannot reorder
    // completed turns. Never block gameplay on disk I/O.
    unawaited(repository.save(state).catchError((Object _) {
      if (!mounted) return;
      setState(() {
        _storageNotice = 'Save failed; progress may not persist';
      });
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (!_loading &&
        (lifecycle == AppLifecycleState.inactive ||
            lifecycle == AppLifecycleState.paused ||
            lifecycle == AppLifecycleState.detached)) {
      _saveCommittedSnapshot();
    }
  }

  Future<void> _discardIncompatibleSave() async {
    setState(() => _loading = true);
    try {
      final repository = _repository;
      if (repository == null) throw StateError('Local storage unavailable');
      await repository.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // Never unlock gameplay or save a new snapshot if deletion failed.
        _needsReset = true;
        _loading = false;
        _storageNotice = 'Could not clear saved game; try again';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      state = GameEngine.newGame(seed: DateTime.now().microsecondsSinceEpoch);
      _needsReset = false;
      _storageNotice = null;
      _loading = false;
    });
    _saveCommittedSnapshot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  void place(int slot, int row, int col) {
    final result = GameEngine.applyMove(state, MoveAction(
        trayIndex: slot, row: row, col: col, expectedTurnId: state.turnId));
    if (result.accepted) {
      setState(() {
        state = result.state;
        _selectedSlot = null;
      });
      _saveCommittedSnapshot();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 500),
        content: Text('Cannot place piece: ${result.error.name}')));
    }
  }

  void restart() {
    setState(() {
      state = GameEngine.newGame(
          seed: DateTime.now().microsecondsSinceEpoch,
          bestScore: state.bestScore);
      _selectedSlot = null;
    });
    _saveCommittedSnapshot();
  }

  Future<void> _showPause() async {
    if (_pauseOpen) return;
    _pauseOpen = true;
    _saveCommittedSnapshot();
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('PAUSED'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'continue'),
              child: const Text('CONTINUE'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'restart'),
              child: const Text('RESTART'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'home'),
              child: const Text('HOME'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'restart') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('CONFIRM RESTART'),
            content: const Text('Start a new game? The current board will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('RESTART GAME'),
              ),
            ],
          ),
        );
        if (mounted && confirmed == true) restart();
      } else if (choice == 'home' && mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      _pauseOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('CLASSIC'),
          backgroundColor: PlasmaColors.background,
          actions: [IconButton(
            icon: const Icon(Icons.pause),
            tooltip: 'Pause',
            onPressed: _showPause,
          )],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _needsReset
                ? SafeArea(child: Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: PlasmaColors.warning, size: 54),
                      const SizedBox(height: 14),
                      Text(_storageNotice ?? 'Saved game cannot be opened',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _discardIncompatibleSave,
                        child: const Text('START NEW GAME'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('HOME'),
                      ),
                    ]),
                  )))
                : SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final heightBudget = constraints.maxHeight -
              (state.gameOver ? 325 : 245);
          final boardSize = (constraints.maxWidth - 32).clamp(
            0.0, heightBudget > 0 ? heightBudget : 0.0,
          ).toDouble();
          return SingleChildScrollView(
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Wrap(alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12, runSpacing: 6,
                children: [Text('BEST ${state.bestScore}',
                    style: const TextStyle(color: PlasmaColors.secondary)),
                  Text('SCORE ${state.score}', style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: PlasmaColors.cyan))])),
            if (_storageNotice != null)
              Text(_storageNotice!, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11,
                      color: PlasmaColors.warning)),
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
                      final targetPiece = candidateData.isEmpty ? null : state.tray[candidateData.first!];
                      final legal = targetPiece != null && GameEngine.canPlace(state, targetPiece, row, col);
                      final colorIndex = state.board[index];
                      final base = colorIndex == null ? PlasmaColors.empty : PlasmaColors.block(colorIndex);
                      return GestureDetector(
                        key: ValueKey('board-tap-$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _selectedSlot == null || state.gameOver
                            ? null
                            : () => place(_selectedSlot!, row, col),
                        child: Semantics(
                        container: true,
                        button: true,
                        label: 'Drop cell row ${row + 1} column ${col + 1}',
                        child: Container(
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
                        ),
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
                  Listener(
                    key: ValueKey('tray-select-$index'),
                    behavior: HitTestBehavior.opaque,
                    // Passive raw-pointer tap selection cannot win the gesture
                    // arena against LongPressDraggable on Android. A true drag
                    // moves much farther than 16dp and is never treated as tap.
                    onPointerDown: (PointerDownEvent event) {
                      _trayTouches[event.pointer] = event.position;
                    },
                    onPointerUp: (PointerUpEvent event) {
                      final down = _trayTouches.remove(event.pointer);
                      if (down == null ||
                          (event.position - down).distance >= 16) return;
                      setState(() {
                        _selectedSlot = _selectedSlot == index ? null : index;
                      });
                    },
                    onPointerCancel: (PointerCancelEvent event) {
                      _trayTouches.remove(event.pointer);
                    },
                    child: Semantics(
                    container: true,
                    button: true,
                    selected: _selectedSlot == index,
                    label: 'Tray slot ${index + 1}',
                    child: LongPressDraggable<int>(
                    data: index,
                    feedback: Transform.translate(
                      offset: const Offset(0, -44),
                      child: Material(color: Colors.transparent,
                        child: _PiecePreview(piece: piece, size: 18))),
                    childWhenDragging: Opacity(opacity: 0.2,
                      child: _PiecePreview(piece: piece, size: 14)),
                    child: _PiecePreview(piece: piece, size: 14),
                    ),
                    ),
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
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('HOME'),
                ),
              ])),
          ])));
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
