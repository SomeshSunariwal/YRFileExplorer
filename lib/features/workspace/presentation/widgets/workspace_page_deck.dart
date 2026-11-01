import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';

/// Keeps tab states alive while sliding only the content below the header.
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
  late final AnimationController controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 320),
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => outgoingId = null);
        }
      });
  int? outgoingId;
  double direction = 1;

  @override
  void didUpdateWidget(covariant WorkspacePageDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeId == widget.activeId) return;
    final oldIndex = widget.pageIds.indexOf(oldWidget.activeId);
    final newIndex = widget.pageIds.indexOf(widget.activeId);
    if (oldIndex < 0 || MediaQuery.disableAnimationsOf(context)) {
      outgoingId = null;
      controller.value = 1;
      return;
    }
    direction = newIndex > oldIndex ? 1 : -1;
    outgoingId = oldWidget.activeId;
    controller.forward(from: 0);
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
            final progress = Curves.easeInOutCubic.transform(controller.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                for (var i = 0; i < widget.children.length; i++)
                  Offstage(
                    key: ValueKey(widget.pageIds[i]),
                    offstage:
                        widget.pageIds[i] != widget.activeId &&
                        widget.pageIds[i] != outgoingId,
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
                            fraction: widget.pageIds[i] == widget.activeId
                                ? direction * (1 - progress)
                                : -direction * progress,
                            surface: theme.scaffoldBackgroundColor,
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
  const _PageMotion({
    required this.fraction,
    required this.surface,
    required super.child,
  });
  @override
  bool updateShouldNotify(_PageMotion oldWidget) =>
      fraction != oldWidget.fraction || surface != oldWidget.surface;
}

/// Moves live body content without moving the tab strip, header or actions.
class WorkspaceBodySlide extends StatelessWidget {
  final Widget child;
  const WorkspaceBodySlide({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final motion = context.dependOnInheritedWidgetOfExactType<_PageMotion>();
    if (motion == null) return child;
    return ClipRect(
      child: FractionalTranslation(
        translation: Offset(motion.fraction, 0),
        child: ColoredBox(color: motion.surface, child: child),
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
