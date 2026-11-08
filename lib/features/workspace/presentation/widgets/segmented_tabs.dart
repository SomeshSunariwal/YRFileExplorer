import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/features/sharing/application/sharing_session.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

class ReferenceTabs extends StatefulWidget {
  final VoidCallback onLocal;
  const ReferenceTabs({super.key, required this.onLocal});
  @override
  State<ReferenceTabs> createState() => _ReferenceTabsState();
}

class _ReferenceTabsState extends State<ReferenceTabs>
    with SingleTickerProviderStateMixin {
  final session = ExplorerWorkspaceSession.instance;
  final sharing = SharingSession.instance;
  final scroll = ScrollController();
  final tabKeys = <String, GlobalKey>{};
  late final AnimationController motion;
  late final Listenable animation;
  Timer? revealTimer;
  final measuredWidths = <String, double>{};
  TextScaler? measuredScaler;
  static const labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
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
    animation = Listenable.merge([
      session,
      motion,
      session.swipeMotion,
      sharing.connection,
    ]);
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
    revealTimer?.cancel();
    revealTimer = Timer(duration + const Duration(milliseconds: 20), () {
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

  void followSwipe(double center) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || session.swipeMotion.value == null || !scroll.hasClients) {
        return;
      }
      final position = scroll.position;
      final target = (center - position.viewportDimension / 2).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if ((position.pixels - target).abs() > .5) position.jumpTo(target);
    });
  }

  @override
  void dispose() {
    revealTimer?.cancel();
    session.removeListener(changed);
    motion.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: TickerMode.valuesOf(context).enabled ? animation : session,
    builder: (context, _) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final tabs =
          <
            ({
              String key,
              String label,
              IconData icon,
              int? id,
              bool isSharing,
              VoidCallback select,
            })
          >[
            (
              key: 'homepage',
              label: 'Homepage',
              icon: Icons.dashboard_outlined,
              id: null,
              isSharing: false,
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
                label: 'Device',
                icon: Icons.phone_android_outlined,
                id: -1,
                isSharing: false,
                select: widget.onLocal,
              ),
            for (final w in session.windows)
              (
                key: 'window-${w.id}',
                label: w.tabLabel,
                icon: w.icon,
                id: w.id,
                isSharing: w.page == 'sharing',
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
      const style = labelStyle;
      final scaler = MediaQuery.textScalerOf(context);
      if (measuredScaler != scaler) {
        measuredScaler = scaler;
        measuredWidths.clear();
      }
      final keys = tabs.map((tab) => tab.key).toSet();
      tabKeys.removeWhere((key, _) => !keys.contains(key));
      final labels = tabs.map((tab) => tab.label).toSet();
      measuredWidths.removeWhere((label, _) => !labels.contains(label));
      // Text layout depends on labels and accessibility scale, not animation frames.
      var selectedWidth = 52.0;
      for (final tab in tabs) {
        final width = measuredWidths.putIfAbsent(tab.label, () {
          final painter = TextPainter(
            text: TextSpan(text: tab.label, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          final width = (painter.width + 24).clamp(52.0, 184.0);
          painter.dispose();
          return width;
        });
        if (width > selectedWidth) selectedWidth = width;
      }
      return SizedBox(
        height: explorerTabHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const minIconWidth = 32.0;
              const preferredIconWidth = 40.0;
              const borderWidth = 2.0;
              final inactiveCount = tabs.length - 1;
              final preferredWidth =
                  inactiveCount * preferredIconWidth +
                  selectedWidth +
                  borderWidth;
              // Keep the natural width until the track hits the header margins.
              final pillWidth = math.min(preferredWidth, constraints.maxWidth);
              final viewport = math.max(0.0, pillWidth - borderWidth);
              final minLabelWidth = math.min(selectedWidth, 72.0);
              final activeWidth = selectedWidth
                  .clamp(
                    minLabelWidth,
                    math.max(
                      minLabelWidth,
                      viewport - inactiveCount * minIconWidth,
                    ),
                  )
                  .toDouble();
              final iconWidth =
                  ((viewport - activeWidth) / math.max(1, inactiveCount)).clamp(
                    minIconWidth,
                    preferredIconWidth,
                  );
              final trackWidth = inactiveCount * iconWidth + activeWidth;
              final indicatorLeft =
                  (fromIndex + (activeIndex - fromIndex) * progress) *
                  iconWidth;
              if (swipe != null && trackWidth > viewport) {
                followSwipe(indicatorLeft + activeWidth / 2);
              }

              return Center(
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : duration,
                  curve: Curves.easeInOutCubic,
                  width: pillWidth,
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
                  child: SingleChildScrollView(
                    controller: scroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(viewport, trackWidth),
                      child: Stack(
                        children: [
                          Positioned(
                            left: indicatorLeft + 2,
                            top: 2,
                            bottom: 2,
                            width: activeWidth - 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: dark
                                    ? const Color(0xff454545)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: dark
                                    ? null
                                    : const [
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
                            children: [
                              for (var i = 0; i < tabs.length; i++)
                                Builder(
                                  key: ValueKey(tabs[i].key),
                                  builder: (context) {
                                    final tab = tabs[i];
                                    final showConnected =
                                        tab.isSharing &&
                                        tab.id != session.activeId &&
                                        sharing.connected;
                                    final start = i == fromIndex ? 1.0 : 0.0;
                                    final end = i == activeIndex ? 1.0 : 0.0;
                                    final weight =
                                        start + (end - start) * progress;
                                    final content = weight >= .5
                                        ? Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            child: Text(
                                              tab.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: style.copyWith(
                                                color: dark
                                                    ? Colors.white
                                                    : explorerInk,
                                              ),
                                            ),
                                          )
                                        : Badge(
                                            isLabelVisible: showConnected,
                                            backgroundColor: dark
                                                ? const Color(0xff58d68d)
                                                : const Color(0xff16843d),
                                            smallSize: 6,
                                            child: Icon(
                                              tab.icon,
                                              size: 18,
                                              color: dark
                                                  ? Colors.white60
                                                  : const Color(0xff6b7785),
                                            ),
                                          );
                                    return SizedBox(
                                      width:
                                          iconWidth +
                                          (activeWidth - iconWidth) * weight,
                                      child: Semantics(
                                        selected: i == activeIndex,
                                        button: true,
                                        label: tab.label,
                                        value: showConnected
                                            ? 'Device connected'
                                            : null,
                                        child: Tooltip(
                                          excludeFromSemantics: true,
                                          message: tab.label,
                                          child: InkWell(
                                            key: tabKeys.putIfAbsent(
                                              tab.key,
                                              GlobalKey.new,
                                            ),
                                            splashFactory:
                                                NoSplash.splashFactory,
                                            highlightColor: Colors.transparent,
                                            hoverColor: Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            onTap: swipe == null
                                                ? tab.select
                                                : null,
                                            child: ExcludeSemantics(
                                              child: ClipRect(
                                                child: OverflowBox(
                                                  minWidth: activeWidth,
                                                  maxWidth: activeWidth,
                                                  child: Center(
                                                    child: Opacity(
                                                      opacity: (2 * weight - 1)
                                                          .abs(),
                                                      child: content,
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
              );
            },
          ),
        ),
      );
    },
  );
}
