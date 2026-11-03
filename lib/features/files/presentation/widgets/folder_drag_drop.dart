import 'package:yr_file_explorer/core/models/json.dart';

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class FolderDragData {
  final String path, name;
  final List<String> paths;
  final List<Json> entries;
  final bool directory;
  final String category;
  FolderDragData(
    this.path,
    this.name, {
    List<String>? paths,
    List<Json>? entries,
    this.directory = true,
    this.category = 'Other',
  }) : paths = List.unmodifiable(paths ?? [path]),
       entries = List.unmodifiable(
         (entries ??
                 [
                   {
                     'path': path,
                     'name': name,
                     'directory': directory,
                     'category': category,
                   },
                 ])
             .map((entry) => Map<String, dynamic>.unmodifiable(entry)),
       );

  bool canMoveInto(String destination) =>
      paths.isNotEmpty &&
      destination.startsWith('/') &&
      paths.every(
        (source) =>
            source.startsWith('/') &&
            source != '/' &&
            destination != source &&
            !destination.startsWith('$source/') &&
            destination != source.substring(0, source.lastIndexOf('/')),
      );
}

/// A hold selects. Selected items require a full second before lifting,
/// leaving quick swipes available for painting selection and deselection.
class FolderDraggable extends StatelessWidget {
  final FolderDragData data;
  final ValueChanged<bool> onDragging;
  final VoidCallback onHold;
  final bool Function() isSelected;
  final Widget child;
  final double iconSize;
  const FolderDraggable({
    super.key,
    required this.data,
    required this.onDragging,
    required this.onHold,
    required this.isSelected,
    required this.child,
    this.iconSize = 60,
  });

  double get feedbackSize =>
      iconSize + (data.entries.length.clamp(1, 3) - 1) * 14;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Drag selected items to move',
    child: _PickupWindowDraggable<FolderDragData>(
      onHold: onHold,
      isSelected: isSelected,
      data: data,
      maxSimultaneousDrags: 1,
      hitTestBehavior: HitTestBehavior.opaque,
      rootOverlay: true,
      onDragStarted: () => onDragging(true),
      onDragEnd: (_) => onDragging(false),
      dragAnchorStrategy: (_, _, _) =>
          Offset(feedbackSize / 2, feedbackSize / 2),
      feedback: Material(
        type: MaterialType.transparency,
        child: Opacity(
          opacity: .5,
          child: SizedBox.square(
            dimension: feedbackSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = data.entries.length.clamp(1, 3) - 1; i >= 0; i--)
                  Positioned(
                    left: i * 14.0,
                    bottom: i * 14.0,
                    child: FileGlyph(data.entries[i], size: iconSize),
                  ),
                if (data.paths.length > 1)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: primaryBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${data.paths.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: child),
    ),
  );
}

class FolderDropTarget extends StatelessWidget {
  final String path;
  final bool enabled;
  final ValueChanged<FolderDragData> onDrop;
  final Widget child;
  const FolderDropTarget({
    super.key,
    required this.path,
    required this.enabled,
    required this.onDrop,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => DragTarget<FolderDragData>(
    onWillAcceptWithDetails: (details) =>
        enabled && details.data.canMoveInto(path),
    onAcceptWithDetails: (details) {
      if (enabled && details.data.canMoveInto(path)) onDrop(details.data);
    },
    builder: (context, candidates, rejected) => DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: candidates.isNotEmpty
            ? primaryBlue.withValues(alpha: .12)
            : Colors.transparent,
        border: candidates.isNotEmpty
            ? Border.all(color: primaryBlue, width: 1.5)
            : null,
      ),
      child: child,
    ),
  );
}

/// Unlike LongPressDraggable, winning the hold does not create a drag avatar.
/// The avatar is started only when the pointer moves during the pickup window.
class _PickupWindowDraggable<T extends Object> extends Draggable<T> {
  final VoidCallback onHold;
  final bool Function() isSelected;
  const _PickupWindowDraggable({
    required this.onHold,
    required this.isSelected,
    required super.child,
    required super.feedback,
    super.data,
    super.maxSimultaneousDrags,
    super.hitTestBehavior,
    super.rootOverlay,
    super.onDragStarted,
    super.onDragEnd,
    super.dragAnchorStrategy,
    super.childWhenDragging,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      _PickupWindowRecognizer(onHold: onHold, isSelected: isSelected)
        ..onStart = onStart;
}

class _PickupWindowRecognizer extends MultiDragGestureRecognizer {
  final VoidCallback onHold;
  final bool Function() isSelected;
  _PickupWindowRecognizer({required this.onHold, required this.isSelected})
    : super(debugOwner: 'folder pickup');
  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _PickupWindowPointer(
        event.position,
        event.kind,
        gestureSettings,
        onHold,
        isSelected(),
      );
  @override
  String get debugDescription => 'folder pickup window';
}

class _PickupWindowPointer extends MultiDragPointerState {
  final VoidCallback onHold;
  Timer? holdTimer;
  final bool selectedAtStart;
  Timer? windowTimer;
  bool held = false, expired = false, arenaAccepted = false;
  GestureMultiDragStartCallback? startDrag;

  _PickupWindowPointer(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
    this.onHold,
    this.selectedAtStart,
  ) {
    if (selectedAtStart) {
      holdTimer = Timer(const Duration(seconds: 1), () {
        held = true;
        if (!arenaAccepted) resolve(GestureDisposition.accepted);
        HapticFeedback.selectionClick();
        tryPickup();
      });
      return;
    }
    // Quick swipes retain scrolling/tab navigation. A stationary long press
    // selects without forcing a drag, then movement can choose to pick it up.
    holdTimer = Timer(kLongPressTimeout, () {
      held = true;
      // Give a full second after the hold selects the folder to choose dragging.
      windowTimer = Timer(const Duration(seconds: 1), () => expired = true);
      if (!arenaAccepted) resolve(GestureDisposition.accepted);
      HapticFeedback.selectionClick();
      onHold();
      tryPickup();
    });
  }

  void tryPickup() {
    if (!held || expired || startDrag == null || pendingDelta == null) return;
    if (!selectedAtStart &&
        pendingDelta!.distance <= computeHitSlop(kind, gestureSettings)) {
      return;
    }
    final start = startDrag!;
    startDrag = null;
    windowTimer?.cancel();
    start(initialPosition);
  }

  @override
  void checkForResolutionAfterMove() {
    if (!held) {
      if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
        resolve(GestureDisposition.rejected);
      }
    } else {
      tryPickup();
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    arenaAccepted = true;
    startDrag = starter;
    tryPickup();
  }

  @override
  void dispose() {
    holdTimer?.cancel();
    windowTimer?.cancel();
    startDrag = null;
    super.dispose();
  }
}
