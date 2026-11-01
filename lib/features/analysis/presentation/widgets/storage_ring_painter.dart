import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

class RingPainter extends CustomPainter {
  final List<Json> categories;
  final double total;
  final Color emptyColor;
  RingPainter(this.categories, this.total, this.emptyColor);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.shortestSide - 16,
      height: size.shortestSide - 16,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = emptyColor);
    var start = -math.pi / 2;
    if (total > 0) {
      for (final cat in categories) {
        final sweep = (cat['size'] as num) / total * math.pi * 2;
        if (sweep > 0) {
          canvas.drawArc(
            rect,
            start,
            sweep,
            false,
            paint..color = categoryColors[cat['name']] ?? Colors.grey,
          );
        }
        start += sweep;
      }
    }
  }

  @override
  bool shouldRepaint(RingPainter oldDelegate) =>
      oldDelegate.total != total ||
      oldDelegate.categories != categories ||
      oldDelegate.emptyColor != emptyColor;
}
