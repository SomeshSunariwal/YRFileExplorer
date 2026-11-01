import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

class ReferenceTabs extends StatefulWidget {
  final bool local;
  final VoidCallback onHome, onLocal;
  const ReferenceTabs({
    super.key,
    required this.local,
    required this.onHome,
    required this.onLocal,
  });
  @override
  State<ReferenceTabs> createState() => _ReferenceTabsState();
}

class _ReferenceTabsState extends State<ReferenceTabs> {
  final scroll = ScrollController();
  final activeKey = GlobalKey();
  bool ready = false;
  int? visibleActive;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ExplorerWorkspaceSession.instance,
    builder: (context, _) {
      final session = ExplorerWorkspaceSession.instance;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260);
      final tabs =
          <
            ({
              String key,
              String label,
              IconData icon,
              int? id,
              VoidCallback select,
            })
          >[
            (
              key: 'homepage',
              label: 'Homepage',
              icon: Icons.dashboard_outlined,
              id: null,
              select: () => session.activate(null),
            ),
            if (session.windows.every(
              (w) =>
                  w.page != 'files' ||
                  w.profile != null ||
                  w.category != null ||
                  w.recent,
            ))
              (
                key: 'home-shortcut',
                label: 'Home',
                icon: Icons.home_outlined,
                id: -1,
                select: widget.onLocal,
              ),
            for (final window in session.windows)
              (
                key: 'window-${window.id}',
                label: window.tabLabel,
                icon: window.icon,
                id: window.id,
                select: () => session.activate(window.id),
              ),
          ];
      final active = tabs.indexWhere((tab) => tab.id == session.activeId);
      final activeIndex = active < 0 ? 0 : active;
      final previous = tabs.indexWhere(
        (tab) => tab.id == session.previousActiveId,
      );
      const textStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
      double labelWidth(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = (painter.width + 24).clamp(52.0, 184.0);
        painter.dispose();
        return width;
      }

      final selectedWidth = labelWidth(tabs[activeIndex].label);
      final indicatorIndex = ready || previous < 0 ? activeIndex : previous;
      final indicatorWidth = ready || previous < 0
          ? selectedWidth
          : labelWidth(tabs[previous].label);
      if (visibleActive != session.activeId || !ready) {
        visibleActive = session.activeId;
        final requested = visibleActive;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future<void>.delayed(duration + const Duration(milliseconds: 20), () {
            if (mounted &&
                requested == session.activeId &&
                activeKey.currentContext != null) {
              Scrollable.ensureVisible(
                activeKey.currentContext!,
                alignment: session.activeId == session.latestOpenedId ? 1 : .5,
                duration: duration,
              );
            }
          });
        });
      }
      return SizedBox(
        height: explorerTabHeight,
        child: Center(
          child: SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                clipBehavior: Clip.antiAlias,
                width: 40.0 * (tabs.length - 1) + selectedWidth + 2,
                height: 28,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xff202020)
                      : const Color(0xffe7e9ec),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: dark ? Colors.white12 : const Color(0xffd0d4d9),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedPositioned(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      left: indicatorIndex * 40.0 + 2,
                      top: 2,
                      bottom: 2,
                      width: indicatorWidth - 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: dark ? const Color(0xff454545) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          _EnteringTab(
                            key: ValueKey(tabs[i].key),
                            animate:
                                tabs[i].id != null &&
                                tabs[i].id == session.latestOpenedId,
                            duration: duration,
                            child: AnimatedContainer(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              width: i == activeIndex ? selectedWidth : 40,
                              height: 28,
                              child: Semantics(
                                selected: i == activeIndex,
                                button: true,
                                label: tabs[i].label,
                                child: Tooltip(
                                  excludeFromSemantics: true,
                                  message: tabs[i].label,
                                  child: InkWell(
                                    key: i == activeIndex ? activeKey : null,
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: tabs[i].select,
                                    child: Center(
                                      child: ExcludeSemantics(
                                        child: i == activeIndex
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                child: Text(
                                                  tabs[i].label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: textStyle.copyWith(
                                                    color: dark
                                                        ? Colors.white
                                                        : explorerInk,
                                                  ),
                                                ),
                                              )
                                            : Icon(
                                                tabs[i].icon,
                                                size: 17,
                                                color: dark
                                                    ? Colors.white60
                                                    : const Color(0xff657180),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _EnteringTab extends StatefulWidget {
  final Widget child;
  final bool animate;
  final Duration duration;
  const _EnteringTab({
    super.key,
    required this.child,
    required this.animate,
    required this.duration,
  });
  @override
  State<_EnteringTab> createState() => _EnteringTabState();
}

class _EnteringTabState extends State<_EnteringTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> animation;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.animate && widget.duration != Duration.zero ? 0 : 1,
    )..forward();
    animation = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    axis: Axis.horizontal,
    sizeFactor: animation,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(.8, 0),
        end: Offset.zero,
      ).animate(animation),
      child: widget.child,
    ),
  );
}
