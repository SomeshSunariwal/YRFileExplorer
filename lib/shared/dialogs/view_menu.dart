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

      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.sizeOf(dialog).height * .85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('View', style: TextStyle(fontSize: 18)),
                ),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.35,
                  children: [
                    for (final kind in ['Icon', 'List', 'Detail'])
                      for (final size in ['Large', 'Medium', 'Small'])
                        Semantics(
                          selected: mode == '$size $kind',
                          child: InkWell(
                            onTap: () =>
                                change('$size $kind', sort, descending),
                            child: Container(
                              color: mode == '$size $kind'
                                  ? primaryBlue.withValues(alpha: .15)
                                  : null,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    kind == 'Icon'
                                        ? Icons.grid_view
                                        : kind == 'List'
                                        ? Icons.view_list
                                        : Icons.view_agenda_outlined,
                                    size: size == 'Large'
                                        ? 32
                                        : size == 'Medium'
                                        ? 27
                                        : 22,
                                    color: primaryBlue,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$size $kind',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                  child: Row(
                    children: [
                      const Text(
                        'Sort',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => change(mode, sort, !descending),
                        icon: Icon(
                          descending ? Icons.south : Icons.north,
                          size: 16,
                        ),
                        label: Text(descending ? 'Descending' : 'Ascending'),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    for (final name in sorts)
                      TextButton(
                        onPressed: () => change(
                          mode,
                          name,
                          sort == name ? !descending : false,
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            color: sort == name
                                ? primaryBlue
                                : Theme.of(dialog).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
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
