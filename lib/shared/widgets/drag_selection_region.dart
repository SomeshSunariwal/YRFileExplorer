import 'dart:async';

import 'package:flutter/material.dart';

/// Paints selection over visible items, without turning a drag into a tab swipe.
class DragSelectionRegion extends StatefulWidget {
  final bool enabled;
  final bool continueFromLongPress;
  final Map<String, GlobalKey> itemKeys;
  final ScrollController scroll;
  final bool Function(String path) isSelected;
  final void Function(String path, bool selected) onSelection;
  final Widget child;
  const DragSelectionRegion({
    super.key,
    required this.enabled,
    this.continueFromLongPress = false,
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
  int? heldPointer;
  String? heldPath;
  bool heldSelected = false, continuingHold = false;

  String? pathAt(Offset position) {
    for (final item in widget.itemKeys.entries) {
      final box = item.value.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          (Offset.zero & box.size).contains(box.globalToLocal(position))) {
        return item.key;
      }
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant DragSelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final path = heldPath;
    // The row's long press has won the gesture arena and toggled selection.
    // Keep following that same pointer instead of requiring a second drag.
    if (widget.continueFromLongPress &&
        widget.enabled &&
        !dragging &&
        heldPointer != null &&
        path != null &&
        widget.isSelected(path) != heldSelected) {
      dragging = continuingHold = true;
      selecting = widget.isSelected(path);
      visited
        ..clear()
        ..add(path);
      startEdgeScroll();
    }
  }

  void paintAtPointer() {
    if (pointer == null) return;
    final path = pathAt(pointer!);
    if (path == null) return;
    selecting ??= !widget.isSelected(path);
    if (visited.add(path) && widget.isSelected(path) != selecting) {
      widget.onSelection(path, selecting!);
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

  void startEdgeScroll() {
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
    continuingHold = false;
    heldPointer = null;
    heldPath = null;
    if (mounted) setState(() => dragging = false);
  }

  @override
  void dispose() {
    edgeScroll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.continueFromLongPress
          ? (event) {
              if (heldPointer != null) return;
              heldPointer = event.pointer;
              heldPath = pathAt(event.position);
              heldSelected = heldPath != null && widget.isSelected(heldPath!);
              pointer = event.position;
            }
          : null,
      onPointerMove: (event) {
        if (event.pointer != heldPointer) return;
        pointer = event.position;
        if (continuingHold) paintAtPointer();
      },
      onPointerUp: (event) {
        if (event.pointer != heldPointer) return;
        if (continuingHold) {
          finish();
        } else {
          heldPointer = null;
          heldPath = null;
        }
      },
      onPointerCancel: (event) {
        if (event.pointer == heldPointer) finish();
      },
      child: widget.child,
    );
  }
}
