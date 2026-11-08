import 'package:yr_file_explorer/shared/widgets/selection_drag_area.dart';
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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fraction = total <= 0
        ? 0.0
        : ((entry['size'] as num) / total).clamp(0.0, 1.0);
    final directory = entry['directory'] == true;
    final metadataStyle = TextStyle(
      fontSize: 11,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final counts = '${entry['files'] ?? 0} / ${entry['folders'] ?? 0}';
    return SelectionHold(
      onHold: onToggle,
      child: Semantics(
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            borderRadius: BorderRadius.circular(10),
            onTap: selectionMode ? onToggle : onOpen,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: FileGlyph(entry, size: 32),
                ),
                Expanded(
                  child: Ink(
                    decoration: BoxDecoration(
                      color: selected
                          ? Color.alphaBlend(
                              primaryBlue.withValues(alpha: .16),
                              theme.colorScheme.surface,
                            )
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: dark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .055),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          width: 1,
                          color: selected
                              ? primaryBlue.withValues(alpha: .6)
                              : dark
                              ? const Color(0xff56636b)
                              : const Color(0xffcbdce5),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: fraction,
                                  heightFactor: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: primaryBlue.withValues(
                                        alpha: dark ? .22 : .12,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 52),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry['name'],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  sizeLabel(entry['size']),
                                                  style: metadataStyle,
                                                ),
                                              ),
                                              Expanded(
                                                child: Semantics(
                                                  label:
                                                      'Share of analyzed data',
                                                  child: Text(
                                                    '${(fraction * 100).toStringAsFixed(2)}%',
                                                    textAlign: TextAlign.center,
                                                    style: metadataStyle,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: directory
                                                    ? Semantics(
                                                        label:
                                                            '${entry['files'] ?? 0} files, ${entry['folders'] ?? 0} subfolders',
                                                        child: Text(
                                                          counts,
                                                          textAlign:
                                                              TextAlign.right,
                                                          style: metadataStyle,
                                                        ),
                                                      )
                                                    : const SizedBox.shrink(),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selectionMode) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 18,
                                        color: selected
                                            ? primaryBlue
                                            : theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
