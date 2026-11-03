import 'package:yr_file_explorer/shared/widgets/explorer_progress_bar.dart';
import 'package:flutter/material.dart';

/// Paints progress over a stable body instead of inserting a row above it.
class ExplorerProgressOverlay extends StatelessWidget {
  final bool active;
  final Widget child;
  const ExplorerProgressOverlay({
    super.key,
    required this.active,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (active)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(child: ExplorerProgressBar(height: 3)),
        ),
    ],
  );
}
