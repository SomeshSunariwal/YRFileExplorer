import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

/// Preserves every tab and slides bodies, while navigation chrome stays fixed.
class WorkspacePageDeck extends StatefulWidget {
  final int activeId;
  final List<int> pageIds;
  final List<Widget> children;
  const WorkspacePageDeck({
    super.key,
    required this.activeId,
    required this.pageIds,
    required this.children,
  });
  @override
  State<WorkspacePageDeck> createState() => _WorkspacePageDeckState();
}

class _WorkspacePageDeckState extends State<WorkspacePageDeck>
    with SingleTickerProviderStateMixin {
  final session = ExplorerWorkspaceSession.instance;
  late final AnimationController controller;
  int? outgoingId, swipeTarget;
  double direction = 1, distance = 0;
  bool swiping = false, fingerDown = false, commitSwipe = false;

  @override
  void initState() {
    super.initState();
    controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 320),
            value: 1,
          )
          ..addListener(publishSwipe)
          ..addStatusListener((status) {
            if (!mounted) return;
            if (swiping &&
                !fingerDown &&
                (status == AnimationStatus.completed ||
                    status == AnimationStatus.dismissed)) {
              finishSwipe(commitSwipe && status == AnimationStatus.completed);
            } else if (!swiping && status == AnimationStatus.completed) {
              setState(() => outgoingId = null);
            }
          });
  }

  void publishSwipe() {
    if (swiping && swipeTarget != null) {
      session.swipeMotion.value = WorkspaceSwipe(
        widget.activeId,
        swipeTarget!,
        controller.value,
      );
    }
  }

  @override
  void didUpdateWidget(covariant WorkspacePageDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeId == widget.activeId) {
      if (swiping &&
          swipeTarget != null &&
          !widget.pageIds.contains(swipeTarget)) {
        finishSwipe(false);
      }
      return;
    }
    swiping = false;
    fingerDown = false;
    swipeTarget = null;
    session.swipeMotion.value = null;
    final oldIndex = widget.pageIds.indexOf(oldWidget.activeId);
    final nextIndex = widget.pageIds.indexOf(widget.activeId);
    if (session.lastSwitchWasSwipe ||
        oldIndex < 0 ||
        MediaQuery.disableAnimationsOf(context)) {
      outgoingId = null;
      controller.value = 1;
      return;
    }
    direction = nextIndex > oldIndex ? 1 : -1;
    outgoingId = oldWidget.activeId;
    controller.forward(from: 0);
  }

  void dragStart(DragStartDetails details) {
    if (controller.isAnimating || widget.pageIds.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() {
      swiping = true;
      fingerDown = true;
      commitSwipe = false;
      distance = 0;
      swipeTarget = null;
      outgoingId = null;
    });
    controller.value = 0;
  }

  void dragUpdate(DragUpdateDetails details) {
    if (!swiping || !fingerDown) return;
    distance += details.primaryDelta ?? 0;
    final nextDirection = distance < 0 ? 1.0 : -1.0;
    final index =
        widget.pageIds.indexOf(widget.activeId) + nextDirection.toInt();
    if (index < 0 || index >= widget.pageIds.length) {
      if (swipeTarget != null) setState(() => swipeTarget = null);
      controller.value = 0;
      session.swipeMotion.value = null;
      return;
    }
    final target = widget.pageIds[index];
    if (direction != nextDirection || swipeTarget != target) {
      setState(() {
        direction = nextDirection;
        swipeTarget = target;
      });
    }
    final width = context.size?.width ?? MediaQuery.sizeOf(context).width;
    final fraction = (distance.abs() / width).clamp(0.0, 1.0);
    if (controller.value == fraction) {
      publishSwipe();
    } else {
      // The controller listener already publishes this frame to the tab strip.
      controller.value = fraction;
    }
  }

  void dragEnd(DragEndDetails details) {
    if (!swiping || !fingerDown) return;
    fingerDown = false;
    final velocity = -(details.primaryVelocity ?? 0) * direction;
    settleSwipe(
      swipeTarget != null &&
          (velocity > 500 || (velocity > -500 && controller.value >= .3)),
    );
  }

  void dragCancel() {
    if (!swiping) return;
    fingerDown = false;
    settleSwipe(false);
  }

  void settleSwipe(bool commit) {
    commitSwipe = commit;
    final target = commit ? 1.0 : 0.0;
    if (swipeTarget == null ||
        controller.value == target ||
        MediaQuery.disableAnimationsOf(context)) {
      finishSwipe(commit);
      return;
    }
    final millis = (220 * (target - controller.value).abs())
        .clamp(80, 220)
        .round();
    controller.animateTo(
      target,
      duration: Duration(milliseconds: millis),
      curve: Curves.easeOutCubic,
    );
  }

  void finishSwipe(bool commit) {
    final target = swipeTarget;
    if (commit && target != null) {
      session.swipeMotion.value = WorkspaceSwipe(widget.activeId, target, 1);
    }
    swiping = false;
    fingerDown = false;
    swipeTarget = null;
    outgoingId = null;
    if (commit && target != null) {
      session.activate(target == 0 ? null : target, fromSwipe: true);
    }
    session.swipeMotion.value = null;
    controller.value = 1;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Theme(
        data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final progress = swiping
                ? controller.value
                : Curves.easeInOutCubic.transform(controller.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                for (var i = 0; i < widget.children.length; i++)
                  Offstage(
                    key: ValueKey(widget.pageIds[i]),
                    offstage:
                        widget.pageIds[i] != widget.activeId &&
                        widget.pageIds[i] !=
                            (swiping ? swipeTarget : outgoingId),
                    child: ExcludeSemantics(
                      excluding: widget.pageIds[i] != widget.activeId,
                      child: IgnorePointer(
                        ignoring:
                            controller.isAnimating ||
                            widget.pageIds[i] != widget.activeId,
                        child: ClipRect(
                          clipper: _PageChromeClipper(
                            showChrome: widget.pageIds[i] == widget.activeId,
                            header:
                                safe.top +
                                explorerTabHeight +
                                explorerHeaderHeight,
                            footer: safe.bottom + explorerFooterHeight + 26,
                          ),
                          child: _PageMotion(
                            fraction:
                                widget.pageIds[i] != widget.activeId &&
                                    widget.pageIds[i] !=
                                        (swiping ? swipeTarget : outgoingId)
                                ? 0
                                : swiping
                                ? widget.pageIds[i] == widget.activeId
                                      ? -direction * progress
                                      : direction * (1 - progress)
                                : widget.pageIds[i] == widget.activeId
                                ? direction * (1 - progress)
                                : -direction * progress,
                            surface: theme.scaffoldBackgroundColor,
                            onStart: dragStart,
                            onUpdate: dragUpdate,
                            onEnd: dragEnd,
                            onCancel: dragCancel,
                            child: widget.children[i],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PageMotion extends InheritedWidget {
  final double fraction;
  final Color surface;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;
  final GestureDragCancelCallback onCancel;
  const _PageMotion({
    required this.fraction,
    required this.surface,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required super.child,
  });
  @override
  bool updateShouldNotify(_PageMotion oldWidget) =>
      fraction != oldWidget.fraction || surface != oldWidget.surface;
}

class WorkspaceBodySlide extends StatelessWidget {
  final Widget child;
  final bool allowTabSwipe;
  const WorkspaceBodySlide({
    super.key,
    required this.child,
    this.allowTabSwipe = true,
  });
  @override
  Widget build(BuildContext context) {
    final motion = context.dependOnInheritedWidgetOfExactType<_PageMotion>();
    if (motion == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: allowTabSwipe ? motion.onStart : null,
      onHorizontalDragUpdate: allowTabSwipe ? motion.onUpdate : null,
      onHorizontalDragEnd: allowTabSwipe ? motion.onEnd : null,
      onHorizontalDragCancel: allowTabSwipe ? motion.onCancel : null,
      child: ClipRect(
        child: FractionalTranslation(
          translation: Offset(motion.fraction, 0),
          child: RepaintBoundary(
            child: ColoredBox(color: motion.surface, child: child),
          ),
        ),
      ),
    );
  }
}

class _PageChromeClipper extends CustomClipper<Rect> {
  final bool showChrome;
  final double header, footer;
  const _PageChromeClipper({
    required this.showChrome,
    required this.header,
    required this.footer,
  });
  @override
  Rect getClip(Size size) => showChrome
      ? Offset.zero & size
      : Rect.fromLTRB(
          0,
          header.clamp(0, size.height),
          size.width,
          (size.height - footer).clamp(
            header.clamp(0, size.height),
            size.height,
          ),
        );
  @override
  bool shouldReclip(_PageChromeClipper oldClipper) =>
      showChrome != oldClipper.showChrome ||
      header != oldClipper.header ||
      footer != oldClipper.footer;
}
