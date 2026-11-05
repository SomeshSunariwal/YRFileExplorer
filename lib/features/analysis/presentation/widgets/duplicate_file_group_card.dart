import 'package:yr_file_explorer/shared/widgets/selection_drag_area.dart';
import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/analysis/domain/analysis_snapshot.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class DuplicateFileGroupCard extends StatelessWidget {
  final DuplicateFileGroup group;
  final bool expanded, enabled;
  final Set<String> selected;
  final VoidCallback onExpand;
  final ValueChanged<String> onToggle;
  final ValueChanged<Json> onOpen;
  const DuplicateFileGroupCard({
    super.key,
    required this.group,
    required this.expanded,
    required this.selected,
    required this.onExpand,
    required this.onToggle,
    required this.onOpen,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Theme.of(context).dividerColor),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          expanded: expanded,
          button: true,
          label: group.name,
          child: InkWell(
            onTap: onExpand,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.copy_all_outlined,
                      size: 19,
                      color: primaryBlue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${group.files.length} copies',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
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
          ),
        ),
        AnimatedSize(
          alignment: Alignment.topCenter,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(height: 1),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Four equal tiles remain visible; extra copies scroll horizontally.
                        final width = (constraints.maxWidth - 38) / 4;
                        final titleHeight =
                            (MediaQuery.textScalerOf(context).scale(10) * 2.5)
                                .ceilToDouble() +
                            2;
                        final sizeHeight =
                            (MediaQuery.textScalerOf(context).scale(10) * 1.25)
                                .ceilToDouble() +
                            2;
                        final tileHeight = width + titleHeight + sizeHeight + 6;
                        return SizedBox(
                          height: tileHeight + 20,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.all(10),
                            itemCount: group.files.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (_, i) => SizedBox(
                              width: width,
                              child: fileCard(
                                context,
                                group.files[i],
                                width,
                                titleHeight,
                                sizeHeight,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    ),
  );

  Widget fileCard(
    BuildContext context,
    Json file,
    double width,
    double titleHeight,
    double sizeHeight,
  ) {
    final path = file['path'] as String;
    final checked = selected.contains(path);
    final colors = Theme.of(context).colorScheme;
    final ext = path.split('.').last.toLowerCase();
    final visual = {
      ...file,
      if (const {
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'bmp',
        'heic',
        'avif',
      }.contains(ext))
        'category': 'Images',
    };
    final card = Material(
      color: checked
          ? Color.alphaBlend(
              primaryBlue.withValues(alpha: .1),
              colors.surfaceContainerLow,
            )
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: checked ? primaryBlue : Theme.of(context).dividerColor,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => onToggle(path) : null,
        onDoubleTap: enabled ? () => onOpen(file) : null,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: width - 12,
                child: FileGlyph(visual, size: width - 12),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: titleHeight,
                width: double.infinity,
                child: Text(
                  file['name'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: sizeHeight,
                width: double.infinity,
                child: Text(
                  sizeLabel(file['size'] ?? 0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.25,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SelectionDragItem(
      id: path,
      enabled: enabled,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            right: -14,
            top: -14,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Transform.scale(
                scale: .75,
                transformHitTests: false,
                child: Checkbox(
                  value: checked,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? primaryBlue
                        : colors.surface,
                  ),
                  semanticLabel:
                      'Select ${file['name']} at ${parentPath(path)} for deletion',
                  onChanged: enabled ? (_) => onToggle(path) : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
