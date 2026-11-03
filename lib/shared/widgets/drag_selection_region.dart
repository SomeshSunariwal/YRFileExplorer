import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Paints selection over visible items, without turning a drag into a tab swipe.
class DragSelectionRegion extends StatefulWidget {
  final bool enabled;
  final Map<String, GlobalKey> itemKeys;
  final ScrollController scroll;
  final bool Function(String path) isSelected;
  final void Function(String path, bool selected) onSelection;
  final Widget child;
  const DragSelectionRegion({
    super.key,
    required this.enabled,
    required this.itemKeys,
    required this.scroll,
    required this.isSelected,
    required this.onSelection,
    required this.child,
  });
  @override
  State<DragSelectionRegion> createState() => _DragSelectionRegionState();
}

class _DragSelectionRegionState extends State<DragSelectionRegion> {
  bool dragging = false;
  bool? selecting;
  Offset? pointer;
  final visited = <String>{};
  Timer? edgeScroll;

  void paintAtPointer() {
    if (pointer == null) return;
    for (final item in widget.itemKeys.entries) {
      final box = item.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if (!(Offset.zero & box.size).contains(box.globalToLocal(pointer!))) {
        continue;
      }
      selecting ??= !widget.isSelected(item.key);
      if (visited.add(item.key) && widget.isSelected(item.key) != selecting) {
        widget.onSelection(item.key, selecting!);
      }
      break;
    }
  }

  void scrollAtEdge() {
    if (!mounted || !dragging || pointer == null || !widget.scroll.hasClients) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final y = box.globalToLocal(pointer!).dy;
    const edge = 48.0;
    final delta = y < edge
        ? -12.0
        : y > box.size.height - edge
        ? 12.0
        : 0.0;
    if (delta == 0) return;
    final position = widget.scroll.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) return;
    widget.scroll.jumpTo(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && dragging) paintAtPointer();
    });
  }

  void start(DragStartDetails details) {
    setState(() => dragging = true);
    visited.clear();
    selecting = null;
    pointer = details.globalPosition;
    paintAtPointer();
    edgeScroll?.cancel();
    edgeScroll = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => scrollAtEdge(),
    );
  }

  void finish() {
    edgeScroll?.cancel();
    pointer = null;
    selecting = null;
    visited.clear();
    if (mounted) setState(() => dragging = false);
  }

  @override
  void dispose() {
    edgeScroll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled || dragging;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: active
          ? {
              PanGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                    () => PanGestureRecognizer(),
                    (recognizer) => recognizer
                      ..dragStartBehavior = DragStartBehavior.down
                      ..onStart = start
                      ..onUpdate = (details) {
                        pointer = details.globalPosition;
                        paintAtPointer();
                      }
                      ..onEnd = (_) {
                        finish();
                      }
                      ..onCancel = finish,
                  ),
            }
          : const {},
      child: widget.child,
    );
  }
}
