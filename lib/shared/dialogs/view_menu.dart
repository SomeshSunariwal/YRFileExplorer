import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/file_categories.dart';

/// The same view chooser is used by local files, applications and archives.
Future<void> showExplorerViewMenu(
  BuildContext context, {
  required String mode,
  required String sort,
  required bool descending,
  required List<String> sorts,
  required void Function(String mode, String sort, bool descending) onChanged,
}) => showDialog<void>(
  context: context,
  builder: (dialog) => StatefulBuilder(
    builder: (dialog, update) {
      void change(String nextMode, String nextSort, bool nextDescending) {
        update(() {
          mode = nextMode;
          sort = nextSort;
          descending = nextDescending;
        });
        onChanged(mode, sort, descending);
      }

      final theme = Theme.of(dialog);
      final colors = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      final kind = mode.split(' ').last;
      final size = mode.split(' ').first;
      Widget option({
        required String label,
        required bool selected,
        required VoidCallback onTap,
        IconData? icon,
      }) => Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(dialog)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: selected
                  ? primaryBlue.withValues(alpha: dark ? .18 : .09)
                  : colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? primaryBlue
                    : colors.outlineVariant.withValues(alpha: .6),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: icon == null ? 10 : 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 23,
                        color: selected ? primaryBlue : colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? primaryBlue : colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.sizeOf(dialog).height * .85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 21,
                        color: primaryBlue,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'View',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close view options',
                        onPressed: () => Navigator.pop(dialog),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      option(
                        label: 'Grid',
                        icon: Icons.grid_view_rounded,
                        selected: kind == 'Icon',
                        onTap: () => change('$size Icon', sort, descending),
                      ),
                      const SizedBox(width: 8),
                      option(
                        label: 'List',
                        icon: Icons.view_list_rounded,
                        selected: kind == 'List',
                        onTap: () => change('$size List', sort, descending),
                      ),
                      const SizedBox(width: 8),
                      option(
                        label: 'Details',
                        icon: Icons.view_agenda_outlined,
                        selected: kind == 'Detail',
                        onTap: () => change('$size Detail', sort, descending),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Item size',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final value in ['Small', 'Medium', 'Large']) ...[
                        if (value != 'Small') const SizedBox(width: 8),
                        option(
                          label: value,
                          selected: size == value,
                          onTap: () => change('$value $kind', sort, descending),
                        ),
                      ],
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 4),
                    child: Divider(height: 1),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sort by',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => change(mode, sort, !descending),
                        icon: Icon(
                          descending
                              ? Icons.south_rounded
                              : Icons.north_rounded,
                          size: 15,
                        ),
                        label: Text(
                          descending ? 'Descending' : 'Ascending',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final name in sorts)
                        ChoiceChip(
                          label: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: sort == name,
                          showCheckmark: false,
                          selectedColor: primaryBlue.withValues(
                            alpha: dark ? .22 : .12,
                          ),
                          side: BorderSide(
                            color: sort == name
                                ? primaryBlue
                                : colors.outlineVariant,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onSelected: (_) => change(
                            mode,
                            name,
                            sort == name ? !descending : false,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  ),
);

int explorerGridColumns(String mode) => mode.startsWith('Large')
    ? 3
    : mode.startsWith('Small')
    ? 5
    : 4;
double explorerGlyphSize(String mode) => mode.startsWith('Large')
    ? 64
    : mode.startsWith('Small')
    ? 36
    : 48;

Future<String?> showExplorerActionMenu(
  BuildContext context,
  List<String> names,
) {
  const icons = <String, IconData>{
    'Hide': Icons.visibility_off_outlined,
    'Unhide': Icons.visibility_outlined,
    'Open with': Icons.open_in_new,
    'Open as': Icons.description_outlined,
    'Favorite': Icons.star_outline,
    'Share': Icons.share_outlined,
    'Encrypt': Icons.lock_outline,
    'Decrypt': Icons.lock_open,
    'Compress': Icons.folder_zip_outlined,
    'Extract': Icons.unarchive_outlined,
    'Properties': Icons.info_outline,
    'Copy to': Icons.copy_outlined,
    'Move to': Icons.drive_file_move_outlined,
    'Analyze': Icons.bar_chart,
    'Copy path': Icons.link,
    'Save to Downloads': Icons.download_outlined,
  };
  return showMenu<String>(
    context: context,
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
    positionBuilder: (context, constraints) {
      final media = MediaQuery.of(context);
      final bottom = 80 + media.padding.bottom;
      final available = constraints.maxHeight - bottom - media.padding.top - 76;
      final height = (names.length * 44.0 + 16).clamp(
        0.0,
        available.clamp(0.0, double.infinity),
      );
      return RelativeRect.fromLTRB(
        constraints.maxWidth - 240,
        constraints.maxHeight - bottom - height,
        8,
        bottom,
      );
    },
    items: [
      for (final name in names)
        PopupMenuItem<String>(
          value: name,
          height: 44,
          child: Row(
            children: [
              Icon(
                icons[name] ?? Icons.more_horiz,
                size: 20,
                color: primaryBlue,
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(name)),
            ],
          ),
        ),
    ],
  );
}
