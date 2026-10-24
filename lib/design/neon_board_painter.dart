import 'package:flutter/material.dart';

import 'tokens.dart';

/// Pure presentation of the 8x8 immutable snapshot. Input and scoring stay
/// inside the existing DragTarget/GestureDetector and GameEngine layers.
class NeonBoardPainter extends CustomPainter {
  NeonBoardPainter({required this.cells}) : assert(cells.length == 64);

  final List<int?> cells;

  // Reuse paints for all 64 cells in one canvas pass. No per-cell animation
  // controllers, images, fonts, external shaders, or game-state mutation.
  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _shine = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final boardRect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(6)),
      _fill..color = PlasmaColors.board,
    );

    final cellWidth = size.width / 8;
    final cellHeight = size.height / 8;
    if (cellWidth <= 0 || cellHeight <= 0) return;
    const inset = 1.5;
    for (var index = 0; index < 64; index++) {
      final row = index ~/ 8;
      final col = index % 8;
      final left = col * cellWidth + inset;
      final top = row * cellHeight + inset;
      final width = cellWidth - 2 * inset;
      final height = cellHeight - 2 * inset;
      if (width <= 0 || height <= 0) continue;

      final rect = Rect.fromLTWH(left, top, width, height);
      final rounded = RRect.fromRectAndRadius(
        rect, const Radius.circular(5),
      );
      final colorIndex = cells[index];
      if (colorIndex == null) {
        canvas.drawRRect(rounded, _fill..color = PlasmaColors.empty);
        canvas.drawRRect(
          rounded, _stroke..color = PlasmaColors.gridStroke,
        );
        continue;
      }

      final color = PlasmaColors.block(colorIndex);
      // Restrained glow is inside the target cell, not over neighbouring cells.
      canvas.drawRRect(
        rounded, _fill..color = color.withValues(alpha: 0.28),
      );
      final inside = RRect.fromRectAndRadius(
        rect.deflate(1.2), const Radius.circular(4),
      );
      canvas.drawRRect(inside, _fill..color = color);
      canvas.drawRRect(
        inside, _stroke..color = PlasmaColors.text.withValues(alpha: 0.6),
      );
      // Upper bevel and dark lower edge improve shape distinction without
      // flashes, particle effects, or dependency on a specific hue.
      canvas.drawLine(
        Offset(left + 5, top + 3),
        Offset(left + width - 5, top + 3),
        _shine..color = PlasmaColors.text.withValues(alpha: 0.66),
      );
      canvas.drawLine(
        Offset(left + 5, top + height - 3),
        Offset(left + width - 5, top + height - 3),
        _shine..color = PlasmaColors.background.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant NeonBoardPainter oldDelegate) =>
      !identical(oldDelegate.cells, cells);
}
