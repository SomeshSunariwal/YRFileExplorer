import 'package:flutter/material.dart';

/// Keep a visible position indicator on overflowing vertical app surfaces.
class ExplorerScrollBehavior extends MaterialScrollBehavior {
  const ExplorerScrollBehavior();
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) != Axis.vertical) return child;
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      thickness: 3,
      radius: const Radius.circular(999),
      child: child,
    );
  }
}
