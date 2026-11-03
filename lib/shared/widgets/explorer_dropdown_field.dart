import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

/// An anchored picker using the same field and menu treatment as New window.
class ExplorerDropdownField<T> extends StatefulWidget {
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const ExplorerDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  State<ExplorerDropdownField<T>> createState() =>
      _ExplorerDropdownFieldState<T>();
}

class _ExplorerDropdownFieldState<T> extends State<ExplorerDropdownField<T>> {
  final anchorKey = GlobalKey();
  bool open = false;

  Future<void> pick() async {
    if (open) return;
    FocusScope.of(context).unfocus();
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    if (!mounted) return;
    final anchor = anchorKey.currentContext?.findRenderObject();
    final overlay = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    if (anchor is! RenderBox || overlay is! RenderBox) return;
    final rect =
        anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
    final theme = Theme.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    setState(() => open = true);
    try {
      final value = await showMenu<T>(
        context: context,
        useRootNavigator: true,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(rect.left, rect.bottom + 6, rect.width, 0),
          Offset.zero & overlay.size,
        ),
        constraints: BoxConstraints(minWidth: rect.width, maxWidth: rect.width),
        color: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.dividerColor),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        popUpAnimationStyle: AnimationStyle(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          reverseDuration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        items: [
          for (final entry in widget.options.entries)
            PopupMenuItem<T>(
              value: entry.key,
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 14,
                        color: entry.key == widget.value
                            ? primaryBlue
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (entry.key == widget.value)
                    const Icon(Icons.check, size: 16, color: primaryBlue),
                ],
              ),
            ),
        ],
      );
      if (mounted && value != null) widget.onChanged(value);
    } finally {
      if (mounted) setState(() => open = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    value: widget.options[widget.value],
    expanded: open,
    child: InkWell(
      key: anchorKey,
      onTap: pick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isFocused: open,
        decoration: InputDecoration(labelText: widget.label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.options[widget.value] ?? '',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            AnimatedRotation(
              turns: open ? .5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: const Icon(
                Icons.expand_more,
                size: 20,
                color: primaryBlue,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
