import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';

/// Floating action surface shared by Homepage, browsing and workspace pages.
class ExplorerBottomBar extends StatelessWidget {
  // Reserve clearance in the scrollable, rather than an opaque footer strip.
  static double contentBottomPadding(BuildContext context) =>
      explorerFooterHeight +
      8 +
      18 +
      MediaQuery.viewPaddingOf(context).bottom +
      12;

  final Widget child;
  const ExplorerBottomBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: dark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .07),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .025),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Material(
            color: explorerChrome(context),
            shape: StadiumBorder(
              side: BorderSide(
                color: explorerLine(context).withValues(alpha: .6),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: explorerFooterHeight + 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
