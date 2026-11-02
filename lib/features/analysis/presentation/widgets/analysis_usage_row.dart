import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class AnalysisUsageRow extends StatelessWidget {
  final Json entry;
  final double total;
  final bool selected, selectionMode;
  final VoidCallback onOpen, onToggle;
  const AnalysisUsageRow({
    super.key,
    required this.entry,
    required this.total,
    required this.selected,
    required this.selectionMode,
    required this.onOpen,
    required this.onToggle,
  });
  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0
        ? 0.0
        : ((entry['size'] as num) / total).clamp(0.0, 1.0);
    final directory = entry['directory'] == true;
    return Semantics(
      selected: selected,
      child: InkWell(
        onLongPress: onToggle,
        onTap: selectionMode ? onToggle : onOpen,
        child: ColoredBox(
          color: selected
              ? primaryBlue.withValues(alpha: .16)
              : Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              children: [
                FileGlyph(entry, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: fraction,
                            child: ColoredBox(
                              color: primaryBlue.withValues(alpha: .10),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 5,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry['name'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    sizeLabel(entry['size']),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    directory
                                        ? '${entry['folders'] ?? 0} folders'
                                        : '—',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    directory
                                        ? '${entry['files'] ?? 0} files'
                                        : 'File',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : selectionMode
                        ? Icons.radio_button_unchecked
                        : Icons.chevron_right,
                    size: 19,
                    color: selected ? primaryBlue : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
