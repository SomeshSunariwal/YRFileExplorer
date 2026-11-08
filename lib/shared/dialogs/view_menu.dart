import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/file_categories.dart';

/// The same view chooser is used by local files, applications and archives.
Future<void> showExplorerViewMenu(
  BuildContext context, {
  required String mode,
  required String sort,
  required bool descending,
  required List<String> sorts,
  required String groupBy,
  required bool groupDescending,
  required void Function(String groupBy, bool descending) onGroupingChanged,
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

      void group(String value, bool reverse) {
        update(() {
          groupBy = value;
          groupDescending = reverse;
        });
        onGroupingChanged(value, reverse);
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
      return ExplorerDialog(
        title: const Text('View'),
        contentPadding: EdgeInsets.zero,
        content: ConstrainedBox(
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
                  const Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 4),
                    child: Divider(height: 1),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Group by',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: groupBy == 'None'
                            ? null
                            : () => group(groupBy, !groupDescending),
                        icon: Icon(
                          groupDescending
                              ? Icons.south_rounded
                              : Icons.north_rounded,
                          size: 15,
                        ),
                        label: Text(
                          groupDescending ? 'Descending' : 'Ascending',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final name in const ['None', 'Name', 'Size', 'Type'])
                        ChoiceChip(
                          label: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: groupBy == name,
                          showCheckmark: false,
                          selectedColor: primaryBlue.withValues(
                            alpha: dark ? .22 : .12,
                          ),
                          side: BorderSide(
                            color: groupBy == name
                                ? primaryBlue
                                : colors.outlineVariant,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onSelected: (_) => group(name, groupDescending),
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

int explorerGridColumns(String mode, {required double width}) =>
    ((width - 20 + 6) / (explorerGlyphSize(mode) + 32 + 6)).floor().clamp(
      1,
      12,
    );

double explorerGridLabelHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(11) * 1.25 * 2 + 4;

double explorerGlyphSize(String mode) => mode.startsWith('Large')
    ? 64
    : mode.startsWith('Small')
    ? 36
    : 48;

Future<String?> showExplorerActionMenu(
  BuildContext context,
  List<String> names, {
  Rect? anchor,
  bool isFavorite = false,
}) {
  const icons = <String, IconData>{
    'Hide': Icons.visibility_off_outlined,
    'Unhide': Icons.visibility_outlined,
    'Open with': Icons.open_in_new,
    'Open as': Icons.description_outlined,
    'Favorite': Icons.star_outline,
    'Move to Private Space': Icons.lock_outline,
    'Move Out': Icons.lock_open_outlined,
    'Share': Icons.share_outlined,
    'Encrypt': Icons.lock_outline,
    'Decrypt': Icons.lock_open,
    'Compress': Icons.folder_zip_outlined,
    'Extract': Icons.unarchive_outlined,
    'Properties': Icons.info_outline,
    'Copy': Icons.copy_outlined,
    'Cut': Icons.content_cut,
    'Copy to': Icons.copy_outlined,
    'Move to': Icons.drive_file_move_outlined,
    'Rename': Icons.edit_outlined,
    'Delete': Icons.delete_outline,
    'Analyze': Icons.bar_chart,
    'Copy path': Icons.link,
    'Save to Downloads': Icons.download_outlined,
  };
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (menuContext, animation, _) => LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final bottom = anchor == null
            ? 80.0 + media.viewPadding.bottom
            : (constraints.maxHeight - anchor.top + 8).clamp(
                media.viewPadding.bottom + 8,
                constraints.maxHeight,
              );
        final right = anchor == null
            ? 12.0
            : (constraints.maxWidth - anchor.right).clamp(
                12.0,
                (constraints.maxWidth - 24).clamp(12.0, double.infinity),
              );
        final available =
            (constraints.maxHeight - bottom - media.padding.top - 16).clamp(
              0.0,
              double.infinity,
            );
        return Stack(
          children: [
            Positioned(
              // Shadow padding is outside the visible menu. Offset it back
              // so it does not become an extra gap above the toolbar.
              right: (right - 16).clamp(0.0, double.infinity),
              bottom: (bottom - 16).clamp(0.0, double.infinity),
              width: (constraints.maxWidth - 24).clamp(0.0, 256.0),
              child: SizeTransition(
                alignment: Alignment.bottomCenter,
                sizeFactor: animation.drive(
                  CurveTween(curve: Curves.easeOutCubic),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (available - 16).clamp(0.0, double.infinity),
                    ),
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      surfaceTintColor: Colors.transparent,
                      elevation: 3,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: names.length,
                        itemBuilder: (context, i) => ListTile(
                          minTileHeight: 44,
                          leading: Icon(
                            names[i] == 'Favorite' && isFavorite
                                ? Icons.star_rounded
                                : icons[names[i]] ?? Icons.more_horiz,
                            size: 20,
                            color: names[i] == 'Favorite' && isFavorite
                                ? const Color(0xffffc107)
                                : primaryBlue,
                          ),
                          title: Text(
                            names[i],
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => Navigator.pop(menuContext, names[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
    transitionBuilder: (context, animation, _, child) => child,
  );
}
