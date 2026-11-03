import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

class ExplorerSelectionHeader extends StatelessWidget {
  final Widget count;
  final VoidCallback? onDone, onSelectAll, onClear;
  final String selectAllLabel;
  const ExplorerSelectionHeader({
    super.key,
    required this.count,
    required this.onDone,
    required this.onSelectAll,
    required this.onClear,
    this.selectAllLabel = 'Select all',
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Done',
        onPressed: onDone,
        icon: const Icon(Icons.check, color: primaryBlue),
      ),
      Expanded(
        child: DefaultTextStyle.merge(
          style: TextStyle(color: explorerForeground(context), fontSize: 18),
          child: count,
        ),
      ),
      IconButton(
        tooltip: selectAllLabel,
        onPressed: onSelectAll,
        icon: const Icon(Icons.select_all, color: primaryBlue),
      ),
      IconButton(
        tooltip: 'Clear selection',
        onPressed: onClear,
        icon: const Icon(Icons.deselect, color: primaryBlue),
      ),
    ],
  );
}
