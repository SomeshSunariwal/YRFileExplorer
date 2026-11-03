import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';

/// Shared History-style surface for every app-owned modal.
class ExplorerDialogSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets insetPadding;
  final double maxWidth;
  const ExplorerDialogSurface({
    super.key,
    required this.child,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 24,
    ),
    this.maxWidth = 400,
  });
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? explorerDarkSurface
        : Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 12,
    insetPadding: insetPadding,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: child,
    ),
  );
}

class ExplorerDialogHeader extends StatelessWidget {
  final Widget title;
  final VoidCallback? onClose;
  final bool canClose;
  const ExplorerDialogHeader({
    super.key,
    required this.title,
    this.onClose,
    this.canClose = true,
  });
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Stack(
        alignment: Alignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 48,
                vertical: title is Text ? 12 : 2,
              ),
              child: Center(
                child: DefaultTextStyle.merge(
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  child: title,
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton(
                tooltip: 'Close',
                onPressed: canClose
                    ? onClose ?? () => Navigator.maybePop(context)
                    : null,
                icon: const Icon(Icons.close, size: 19),
              ),
            ),
          ),
        ],
      ),
      const Divider(height: 1),
    ],
  );
}

class ExplorerDialog extends StatelessWidget {
  final Widget? title, content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry contentPadding;
  final VoidCallback? onClose;
  final bool canClose;
  final MainAxisAlignment actionsAlignment;
  final double maxWidth;
  const ExplorerDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.contentPadding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    this.onClose,
    this.canClose = true,
    this.actionsAlignment = MainAxisAlignment.center,
    this.maxWidth = 400,
  });
  @override
  Widget build(BuildContext context) => ExplorerDialogSurface(
    maxWidth: maxWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExplorerDialogHeader(
          title: title ?? const SizedBox.shrink(),
          onClose: onClose,
          canClose: canClose,
        ),
        if (content != null)
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: contentPadding,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 14),
                  child: content!,
                ),
              ),
            ),
          ),
        if (actions?.isNotEmpty == true) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: OverflowBar(
              alignment: actionsAlignment,
              spacing: 8,
              overflowSpacing: 4,
              children: actions!,
            ),
          ),
        ],
      ],
    ),
  );
}

class ExplorerChoiceDialog extends StatelessWidget {
  final double maxWidth;
  final Widget? title;
  final List<Widget>? children;
  const ExplorerChoiceDialog({
    super.key,
    this.title,
    this.children,
    this.maxWidth = 400,
  });
  @override
  Widget build(BuildContext context) => ExplorerDialog(
    maxWidth: maxWidth,
    title: title,
    contentPadding: EdgeInsets.zero,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < (children?.length ?? 0); i++) ...[
          if (i > 0) const Divider(height: 1),
          children![i],
        ],
      ],
    ),
  );
}

/// Consistent icon, text and touch target for modal list actions.
class ExplorerChoiceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const ExplorerChoiceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 48,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    horizontalTitleGap: 12,
    leading: Icon(icon, size: 20, color: primaryBlue),
    title: Text(label, style: const TextStyle(fontSize: 14)),
    onTap: onTap,
  );
}
