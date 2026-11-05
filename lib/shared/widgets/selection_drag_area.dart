import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'drag_selection_region.dart';

import 'package:yr_file_explorer/core/theme/explorer_scroll_behavior.dart';

/// A single hold duration for every selectable tile, independent of its layout.
class SelectionHold extends StatelessWidget {
  final VoidCallback? onHold;
  final Widget child;
  const SelectionHold({super.key, required this.onHold, required this.child});

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: onHold == null
        ? const {}
        : {
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    duration: const Duration(seconds: 1),
                  ),
                  (recognizer) => recognizer..onLongPress = onHold,
                ),
          },
    child: child,
  );
}

/// Supplies selection painting and edge scrolling to lazy lists and grids.
class SelectionDragArea extends StatefulWidget {
  final Set<String> selected;
  final void Function(String id, bool selected) onSelection;
  final Widget child;
  final bool enabled;
  const SelectionDragArea({
    super.key,
    required this.selected,
    required this.onSelection,
    required this.child,
    this.enabled = true,
  });

  @override
  State<SelectionDragArea> createState() => _SelectionDragAreaState();
}

class _SelectionDragAreaState extends State<SelectionDragArea> {
  final keys = <String, GlobalKey>{};
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SelectionScope(
    state: this,
    child: PrimaryScrollController(
      controller: scroll,
      child: ScrollConfiguration(
        behavior: const ExplorerScrollBehavior(),
        child: DragSelectionRegion(
          enabled: widget.enabled && widget.selected.isNotEmpty,
          continueFromLongPress: widget.enabled,
          itemKeys: keys,
          scroll: scroll,
          isSelected: widget.selected.contains,
          onSelection: widget.onSelection,
          child: widget.child,
        ),
      ),
    ),
  );
}

class _SelectionScope extends InheritedWidget {
  final _SelectionDragAreaState state;
  const _SelectionScope({required this.state, required super.child});
  @override
  bool updateShouldNotify(_SelectionScope oldWidget) => true;
}

/// Registers only mounted tiles, keeping hit testing bounded on large folders.
class SelectionDragItem extends StatefulWidget {
  final String id;
  final Widget child;
  final bool enabled;
  const SelectionDragItem({
    super.key,
    required this.id,
    required this.child,
    this.enabled = true,
  });
  @override
  State<SelectionDragItem> createState() => _SelectionDragItemState();
}

class _SelectionDragItemState extends State<SelectionDragItem> {
  final itemKey = GlobalKey();
  _SelectionDragAreaState? area;
  String? registeredId;

  void unregister() {
    if (area?.keys[registeredId] == itemKey) {
      area!.keys.remove(registeredId);
    }
  }

  @override
  void dispose() {
    unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = context
        .dependOnInheritedWidgetOfExactType<_SelectionScope>()
        ?.state;
    if (area != next || registeredId != widget.id) unregister();
    area = next;
    registeredId = widget.id;
    final active = widget.enabled && area?.widget.enabled == true;
    if (active) {
      area!.keys[widget.id] = itemKey;
    } else {
      unregister();
    }
    return SelectionHold(
      key: itemKey,
      onHold: active
          ? () => area!.widget.onSelection(
              widget.id,
              !area!.widget.selected.contains(widget.id),
            )
          : null,
      child: widget.child,
    );
  }
}
