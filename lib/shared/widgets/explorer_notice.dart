import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';

OverlayEntry? _currentNotice;

void dismissExplorerNotice() {
  final entry = _currentNotice;
  _currentNotice = null;
  if (entry != null) {
    entry.remove();
    entry.dispose();
  }
}

/// A rounded notification rises from the toolbar without moving page content.
void showExplorerNotice(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_outline,
  bool error = false,
  Duration duration = const Duration(seconds: 3),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (!context.mounted) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  dismissExplorerNotice();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NoticeBox(
      message: message,
      icon: icon,
      error: error,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      onClosed: () {
        if (_currentNotice != entry) return;
        _currentNotice = null;
        entry.remove();
        entry.dispose();
      },
    ),
  );
  _currentNotice = entry;
  overlay.insert(entry);
}

class _NoticeBox extends StatefulWidget {
  final String message;
  final IconData icon;
  final bool error;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClosed;
  const _NoticeBox({
    required this.message,
    required this.icon,
    required this.error,
    required this.duration,
    this.actionLabel,
    this.onAction,
    required this.onClosed,
  });
  @override
  State<_NoticeBox> createState() => _NoticeBoxState();
}

class _NoticeBoxState extends State<_NoticeBox>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController motion;
  Timer? timer;
  bool closing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (timer != null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.value = 1;
    } else {
      motion.forward();
    }
    timer = Timer(widget.duration + motion.duration!, close);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) widget.onClosed();
  }

  Future<void> close() async {
    if (closing) return;
    closing = true;
    timer?.cancel();
    try {
      if (!MediaQuery.disableAnimationsOf(context)) {
        await motion.reverse().orCancel;
      }
      if (mounted) widget.onClosed();
    } on TickerCanceled {
      /* Replaced by a newer notice. */
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    motion.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), media = MediaQuery.of(context);
    final accent = widget.error ? theme.colorScheme.error : primaryBlue;
    final bottom = (media.padding.bottom + explorerFooterHeight + 28).clamp(
      media.viewInsets.bottom + 8,
      double.infinity,
    );
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: motion,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            ),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .45), end: Offset.zero)
                  .animate(
                    CurvedAnimation(parent: motion, curve: Curves.easeOutCubic),
                  ),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: theme.colorScheme.surface,
                  elevation: theme.brightness == Brightness.dark ? 0 : 6,
                  shadowColor: Colors.black.withValues(alpha: .2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: accent.withValues(alpha: .3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
                    child: Row(
                      children: [
                        Icon(widget.icon, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (widget.actionLabel != null &&
                            widget.onAction != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              widget.onAction!();
                              close();
                            },
                            child: Text(widget.actionLabel!),
                          ),
                        IconButton(
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(36),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: close,
                          tooltip: 'Dismiss notification',
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
