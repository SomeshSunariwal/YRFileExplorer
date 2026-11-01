import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

/// The full-width Homepage location contracts as local navigation enters.
class ExplorerNavigationHeader extends StatefulWidget {
  final Widget location;
  final bool homepage;
  final VoidCallback? onBack, onClose;
  const ExplorerNavigationHeader({
    super.key,
    required this.location,
    this.homepage = false,
    this.onBack,
    this.onClose,
  });
  @override
  State<ExplorerNavigationHeader> createState() =>
      _ExplorerNavigationHeaderState();
}

class _ExplorerNavigationHeaderState extends State<ExplorerNavigationHeader>
    with SingleTickerProviderStateMixin {
  final session = ExplorerWorkspaceSession.instance;
  late final AnimationController motion;
  int? activeId;
  @override
  void initState() {
    super.initState();
    activeId = session.activeId;
    motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: session.previousActiveId == null ? 0 : 1,
    );
    session.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) animate();
    });
  }

  void animate() {
    motion.animateTo(
      session.activeId == null ? 0 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  void changed() {
    if (activeId == session.activeId) return;
    final fromHomepage = activeId == null;
    activeId = session.activeId;
    // Offstage tabs have muted tickers: reset to the shared source geometry.
    motion.value = fromHomepage ? 0 : 1;
    animate();
  }

  @override
  void dispose() {
    session.removeListener(changed);
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    builder: (context, _) {
      final progress = motion.value;
      return ExplorerHeaderFrame(
        separators: false,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8 + 40 * progress),
                  child: widget.location,
                ),
              ),
              for (final left in [true, false])
                Positioned(
                  left: left ? 0 : null,
                  right: left ? null : 0,
                  top: 0,
                  bottom: 0,
                  width: 48,
                  child: ExcludeSemantics(
                    excluding: widget.homepage,
                    child: IgnorePointer(
                      ignoring: widget.homepage || motion.isAnimating,
                      child: FractionalTranslation(
                        translation: Offset(
                          (left ? -1 : 1) * (1 - progress),
                          0,
                        ),
                        child: Opacity(
                          opacity: progress,
                          child: IconButton(
                            tooltip: left ? 'Back' : 'Close window',
                            onPressed: left ? widget.onBack : widget.onClose,
                            icon: Icon(
                              left ? Icons.arrow_back : Icons.cancel_outlined,
                              size: left ? 22 : 20,
                              color: primaryBlue,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final left in [true, false])
                Positioned(
                  left: left ? 48 : null,
                  right: left ? null : 48,
                  top: 8,
                  bottom: 8,
                  child: Opacity(
                    opacity: progress,
                    child: Container(width: 1, color: explorerLine(context)),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
