import 'package:flutter/material.dart';

const explorerInk = Color(0xff1c2938);
const explorerCanvas = Color(0xfff3f6fa);
const explorerTabHeight = 36.0;
const explorerHeaderHeight = 44.0;
const explorerFooterHeight = 56.0;
const explorerDarkBase = Color(0xff292929);
const explorerDarkSurface = Color(0xff333333);

Color explorerChrome(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? explorerDarkBase
    : Colors.white;
Color explorerForeground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xfff2f2f2)
    : explorerInk;
Color explorerLine(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff494949)
    : const Color(0xffdce2e8);

class ExplorerHeaderFrame extends StatelessWidget {
  final Widget child;
  final bool separators;
  const ExplorerHeaderFrame({
    super.key,
    required this.child,
    this.separators = true,
  });
  @override
  Widget build(BuildContext context) => Container(
    height: explorerHeaderHeight,
    decoration: BoxDecoration(
      color: explorerChrome(context),
      border: Border(
        top: BorderSide(color: explorerLine(context)),
        bottom: BorderSide(color: explorerLine(context)),
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(child: child),
        if (separators) ...[
          Positioned(
            left: 48,
            top: 8,
            bottom: 8,
            child: Container(width: 1, color: explorerLine(context)),
          ),
          Positioned(
            right: 48,
            top: 8,
            bottom: 8,
            child: Container(width: 1, color: explorerLine(context)),
          ),
        ],
      ],
    ),
  );
}

class ExplorerLocationPill extends StatelessWidget {
  final Widget child;
  const ExplorerLocationPill({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xff3b3b3b)
          : const Color(0xffeaf6f9),
      border: Border.all(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff565656)
            : const Color(0xffc9e8ef),
      ),
      borderRadius: BorderRadius.circular(40),
    ),
    child: DefaultTextStyle(
      style: TextStyle(
        fontSize: 14,
        color: explorerForeground(context),
        fontWeight: FontWeight.w500,
      ),
      child: child,
    ),
  );
}

class ExplorerPageTransitions extends PageTransitionsBuilder {
  const ExplorerPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(.08, 0),
        end: Offset.zero,
      ).animate(eased),
      child: child,
    );
  }
}

class ExplorerPageRoute<T> extends PageRouteBuilder<T> {
  ExplorerPageRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          return SlideTransition(
            position: animation.drive(
              Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeInOutCubic)),
            ),
            child: child,
          );
        },
      );
}
