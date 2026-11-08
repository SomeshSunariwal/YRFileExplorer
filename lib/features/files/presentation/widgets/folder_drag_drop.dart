import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/gestures/interaction_timing.dart';

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

/// The first hold selects and paints selection. A separate hold while selection
/// is active lifts items, leaving quick swipes available for selection changes.
class FolderDraggable extends StatefulWidget {
  final FolderDragData data;
  final Map<String, Offset> Function() pickupOrigins;
  final ValueChanged<bool> onDragging;
  final VoidCallback onHold;
  final bool Function() isSelected;
  final Widget child;
  final double iconSize;
  const FolderDraggable({
    super.key,
    required this.data,
    required this.pickupOrigins,
    required this.onDragging,
    required this.onHold,
    required this.isSelected,
    required this.child,
    this.iconSize = 60,
  });

  @override
  State<FolderDraggable> createState() => _FolderDraggableState();
}

class _FolderDraggableState extends State<FolderDraggable> {
  ValueNotifier<Offset>? _activePosition;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final iconSize = widget.iconSize;
    final stackCount = data.entries.length.clamp(1, 3);
    final feedbackSize = iconSize + (stackCount - 1) * 14;
    final anchor = Offset(feedbackSize / 2, feedbackSize / 2);
    var origins = const <String, Offset>{};
    ValueNotifier<Offset>? position;
    return Tooltip(
      message: 'Drag selected items to move',
      child: _PickupWindowDraggable<FolderDragData>(
        onHold: widget.onHold,
        isSelected: widget.isSelected,
        data: data,
        maxSimultaneousDrags: 1,
        hitTestBehavior: HitTestBehavior.opaque,
        rootOverlay: true,
        onDragStarted: () => widget.onDragging(true),
        onDragEnd: (_) {
          _activePosition = null;
          widget.onDragging(false);
        },
        onDragUpdate: (details) {
          final active = _activePosition;
          // Match Draggable's own delta accumulation, including pending
          // movement delivered immediately after the hold is accepted.
          if (active != null) active.value += details.delta;
        },
        dragAnchorStrategy: (_, context, pointer) {
          origins = MediaQuery.disableAnimationsOf(context)
              ? const {}
              : widget.pickupOrigins();
          position = origins.isEmpty ? null : ValueNotifier(pointer - anchor);
          _activePosition = position;
          return anchor;
        },
        // Draggable keeps this feedback for the lifetime of the drag, so
        // later file list rebuilds cannot replace the pickup snapshot.
        feedback: Builder(
          builder: (_) => _FolderDragFeedback(
            data: data,
            origins: origins,
            position: position,
            iconSize: iconSize,
            size: feedbackSize,
            stackCount: stackCount,
          ),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: widget.child,
        ),
      ),
    );
  }
}

class _FolderDragFeedback extends StatelessWidget {
  final FolderDragData data;
  final Map<String, Offset> origins;
  final ValueNotifier<Offset>? position;
  final double iconSize, size;
  final int stackCount;

  const _FolderDragFeedback({
    required this.data,
    required this.origins,
    required this.position,
    required this.iconSize,
    required this.size,
    required this.stackCount,
  });

  @override
  Widget build(BuildContext context) {
    final glyphs = {
      for (var i = data.entries.length - 1; i >= 0; i--)
        if (i < stackCount || origins.containsKey(data.entries[i]['path']))
          i: FileGlyph(data.entries[i], size: iconSize),
    };
    final badge = data.paths.length > 1
        ? Container(
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
          )
        : null;
    final halfIcon = Offset(iconSize / 2, iconSize / 2);
    final stackCenter = Offset(size / 2, size / 2) - halfIcon;

    Widget preview(double progress, Offset topLeft) {
      final easing = Curves.easeOutCubic.transform(progress);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (final glyph in glyphs.entries)
            if (progress < 1 || glyph.key < stackCount)
              ghost(glyph, progress, easing, topLeft, halfIcon, stackCenter),
          if (badge != null)
            Positioned(
              right: 0,
              top: 0,
              child: Opacity(
                opacity: ((progress - .55) / .45).clamp(0.0, 1.0),
                child: badge,
              ),
            ),
        ],
      );
    }

    final dragPosition = position;
    return Material(
      type: MaterialType.transparency,
      child: Opacity(
        opacity: .5,
        child: SizedBox.square(
          dimension: size,
          child: dragPosition == null
              ? preview(1, Offset.zero)
              : TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 500),
                  tween: Tween(begin: 0, end: 1),
                  builder: (_, progress, _) => progress == 1
                      ? preview(1, Offset.zero)
                      : ValueListenableBuilder<Offset>(
                          valueListenable: dragPosition,
                          builder: (_, topLeft, _) =>
                              preview(progress, topLeft),
                        ),
                ),
        ),
      ),
    );
  }

  Widget ghost(
    MapEntry<int, FileGlyph> glyph,
    double progress,
    double easing,
    Offset topLeft,
    Offset halfIcon,
    Offset stackCenter,
  ) {
    final index = glyph.key;
    final inStack = index < stackCount;
    final step = index * 14.0;
    final destination = inStack
        ? Offset(step, size - iconSize - step)
        : stackCenter;
    final origin = origins[data.entries[index]['path']];
    final offset = origin == null || progress == 1
        ? destination
        : Offset.lerp(origin - topLeft - halfIcon, destination, easing)!;
    final opacity = inStack
        ? (origin == null ? easing : 1.0)
        : ((1 - progress) / .4).clamp(0.0, 1.0);
    return Positioned(
      key: ValueKey(index),
      left: offset.dx,
      top: offset.dy,
      child: Opacity(opacity: opacity, child: glyph.value),
    );
  }
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

/// Capture selection mode at pointer-down: the first hold can never lift items,
/// even after it changes the selection. A later hold can start a move.
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
    super.onDragUpdate,
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
  bool held = false, arenaAccepted = false;
  GestureMultiDragStartCallback? startDrag;

  _PickupWindowPointer(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
    this.onHold,
    this.selectedAtStart,
  ) {
    if (selectedAtStart) {
      holdTimer = Timer(InteractionTiming.hold, () {
        held = true;
        if (!arenaAccepted) resolve(GestureDisposition.accepted);
        HapticFeedback.selectionClick();
        tryPickup();
      });
      return;
    }
    // The initial contact is selection-only for its entire lifetime.
    holdTimer = Timer(InteractionTiming.hold, () {
      held = true;
      if (!arenaAccepted) resolve(GestureDisposition.accepted);
      HapticFeedback.selectionClick();
      onHold();
    });
  }

  void tryPickup() {
    if (!selectedAtStart ||
        !held ||
        startDrag == null ||
        pendingDelta == null) {
      return;
    }
    final start = startDrag!;
    startDrag = null;
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
    startDrag = null;
    super.dispose();
  }
}
