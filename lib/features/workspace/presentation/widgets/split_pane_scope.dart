import 'package:flutter/widgets.dart';

/// A tool pane contributes its actions to the split workspace's shared footer.
class SplitPaneScope extends InheritedWidget {
  final ValueChanged<Widget> onToolbar;
  const SplitPaneScope({
    super.key,
    required this.onToolbar,
    required super.child,
  });
  static SplitPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SplitPaneScope>();
  @override
  bool updateShouldNotify(SplitPaneScope oldWidget) => false;
}
