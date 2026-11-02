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

class _ReferenceTabsState extends State<ReferenceTabs>
    with SingleTickerProviderStateMixin {
  final session = ExplorerWorkspaceSession.instance;
  final scroll = ScrollController();
  final tabKeys = <String, GlobalKey>{};
  late final AnimationController motion;
  int? activeId, fromId;
  static const duration = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    activeId = session.activeId;
    fromId = session.previousActiveId;
    motion = AnimationController(
      vsync: this,
      duration: duration,
      value: session.lastSwitchWasSwipe || fromId == activeId ? 1 : 0,
    );
    session.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        start();
        revealActive();
      }
    });
  }

  void start() {
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.value = 1;
    } else {
      motion.forward();
    }
  }

  void changed() {
    if (activeId == session.activeId) return;
    fromId = activeId;
    activeId = session.activeId;
    if (session.lastSwitchWasSwipe) {
      fromId = activeId;
      motion.value = 1;
    } else {
      motion.value = 0;
      start();
    }
    revealActive();
  }

  void revealActive() {
    final requested = session.activeId;
    Future<void>.delayed(duration + const Duration(milliseconds: 20), () {
      final key = tabKeys[requested == null ? 'homepage' : 'window-$requested'];
      if (mounted &&
          requested == session.activeId &&
          key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          alignment: .5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        );
      }
    });
  }

  @override
  void dispose() {
    session.removeListener(changed);
    motion.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([session, motion, session.swipeMotion]),
    builder: (context, _) {
      final dark = Theme.of(context).brightness == Brightness.dark;
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
            for (final w in session.windows)
              (
                key: 'window-${w.id}',
                label: w.tabLabel,
                icon: w.icon,
                id: w.id,
                select: () => session.activate(w.id),
              ),
          ];
      final swipe = session.swipeMotion.value;
      final targetId = swipe == null
          ? session.activeId
          : swipe.toId == 0
          ? null
          : swipe.toId;
      final sourceId = swipe == null
          ? fromId
          : swipe.fromId == 0
          ? null
          : swipe.fromId;
      final activeIndex = tabs
          .indexWhere((tab) => tab.id == targetId)
          .clamp(0, tabs.length - 1);
      final previous = tabs.indexWhere((tab) => tab.id == sourceId);
      final fromIndex = previous < 0 ? activeIndex : previous;
      final progress =
          swipe?.progress ?? Curves.easeInOutCubic.transform(motion.value);
      const style = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
      // A shared selected slot keeps Homepage and Home the same overall width.
      var selectedWidth = 52.0;
      for (final tab in tabs) {
        final painter = TextPainter(
          text: TextSpan(text: tab.label, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = (painter.width + 24).clamp(52.0, 184.0);
        if (width > selectedWidth) selectedWidth = width;
        painter.dispose();
      }
      if (swipe != null &&
          scroll.hasClients &&
          scroll.position.maxScrollExtent > 0) {
        final center =
            (fromIndex + (activeIndex - fromIndex) * progress) * 40 +
            selectedWidth / 2;
        final target = (center - scroll.position.viewportDimension / 2).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              session.swipeMotion.value != null &&
              scroll.hasClients &&
              (scroll.offset - target).abs() > .5) {
            scroll.jumpTo(target);
          }
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
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : duration,
                curve: Curves.easeInOutCubic,
                width: 40 * (tabs.length - 1) + selectedWidth + 2,
                height: 28,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xff202020)
                      : const Color(0xffe7e9ec),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: dark ? Colors.white12 : const Color(0xffd0d4d9),
                  ),
                ),
                // Lay out the row at its destination width while the outer
                // viewport grows. An offstage header may resume mid-growth;
                // constraining the full row to that intermediate width caused
                // a RenderFlex overflow on the first return from a new tab.
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 40 * (tabs.length - 1) + selectedWidth,
                  maxWidth: 40 * (tabs.length - 1) + selectedWidth,
                  child: Stack(
                    children: [
                      Positioned(
                        left:
                            (fromIndex + (activeIndex - fromIndex) * progress) *
                                40 +
                            2,
                        top: 2,
                        bottom: 2,
                        width: selectedWidth - 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xff454545)
                                : Colors.white,
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
                            Builder(
                              key: ValueKey(tabs[i].key),
                              builder: (context) {
                                final start = i == fromIndex ? 1.0 : 0.0;
                                final end = i == activeIndex ? 1.0 : 0.0;
                                final weight = start + (end - start) * progress;
                                return SizedBox(
                                  width: 40 + (selectedWidth - 40) * weight,
                                  height: 28,
                                  child: Semantics(
                                    selected: i == activeIndex,
                                    button: true,
                                    label: tabs[i].label,
                                    child: Tooltip(
                                      excludeFromSemantics: true,
                                      message: tabs[i].label,
                                      child: InkWell(
                                        key: tabKeys.putIfAbsent(
                                          tabs[i].key,
                                          () => GlobalKey(),
                                        ),
                                        splashFactory: NoSplash.splashFactory,
                                        highlightColor: Colors.transparent,
                                        hoverColor: Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: swipe == null
                                            ? tabs[i].select
                                            : null,
                                        child: ExcludeSemantics(
                                          child: Center(
                                            // Keep a fixed type size as slots move. Switching
                                            // immediately to the target label flashes the
                                            // old tab's icon inside the departing pill.
                                            child: ClipRect(
                                              child: OverflowBox(
                                                minWidth: selectedWidth,
                                                maxWidth: selectedWidth,
                                                child: weight >= .5
                                                    ? Opacity(
                                                        opacity:
                                                            ((weight - .5) * 2)
                                                                .clamp(
                                                                  0.0,
                                                                  1.0,
                                                                ),
                                                        child: Text(
                                                          tabs[i].label,
                                                          maxLines: 1,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: style.copyWith(
                                                            color: dark
                                                                ? Colors.white
                                                                : explorerInk,
                                                          ),
                                                        ),
                                                      )
                                                    : Opacity(
                                                        opacity:
                                                            (1 - weight * 2)
                                                                .clamp(
                                                                  0.0,
                                                                  1.0,
                                                                ),
                                                        child: Icon(
                                                          tabs[i].icon,
                                                          size: 18,
                                                          color: dark
                                                              ? Colors.white60
                                                              : const Color(
                                                                  0xff6b7785,
                                                                ),
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
