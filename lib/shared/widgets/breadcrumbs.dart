import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

/// One rounded path surface containing the last three clickable locations.
class ExplorerBreadcrumbs extends StatelessWidget {
  final List<(String label, String path)> entries;
  final ValueChanged<String> onNavigate;
  final VoidCallback? onCurrent;
  const ExplorerBreadcrumbs({
    super.key,
    required this.entries,
    required this.onNavigate,
    this.onCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final visible = entries
        .skip((entries.length - 3).clamp(0, entries.length))
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ExplorerLocationPill(
        child: Row(
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                const Icon(Icons.chevron_right, size: 20, color: primaryBlue),
              Expanded(
                child: Tooltip(
                  message: visible[i].$1,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: i == visible.length - 1 && onCurrent != null
                        ? onCurrent
                        : () => onNavigate(visible[i].$2),
                    child: Center(
                      child: Text(
                        visible[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: i == visible.length - 1
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: explorerForeground(context).withValues(
                            alpha: i == visible.length - 1 ? 1 : .75,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
