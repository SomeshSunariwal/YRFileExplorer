import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/features/workspace/presentation/widgets/window_panel_tabs.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/window_preview_card.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/new_window_dialog.dart';

Future<void> showExplorerWindows(BuildContext context) async {
  final session = ExplorerWorkspaceSession.instance;
  await session.beforeSwitch?.call();
  if (!context.mounted) return;
  return showDialog<void>(
    context: context,
    builder: (dialog) => ExplorerDialogSurface(
      maxWidth: 560,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          child: DefaultTabController(
            length: 2,
            child: AnimatedBuilder(
              animation: session.windowChanges,
              builder: (_, _) {
                final files = session.clipboardItems?.call() ?? <String>[];
                final media = MediaQuery.of(dialog);
                final panelWidth = math.min(560.0, media.size.width - 40);
                final cardWidth = (panelWidth - 36) / 2;
                final rowCount = (session.count + 1) ~/ 2;
                final gridHeight =
                    24 +
                    rowCount * cardWidth / .90 +
                    math.max(0, rowCount - 1) * 12;
                final maxHeight = math.max(
                  180.0,
                  math.min(
                    media.size.height * .80,
                    media.size.height -
                        media.padding.vertical -
                        media.viewInsets.bottom -
                        40,
                  ),
                );
                final panelHeight = math.min(
                  maxHeight,
                  math.max(240.0, gridHeight + 108),
                );

                Widget preview(int? id, String label, IconData icon) =>
                    WindowPreviewCard(
                      label: label,
                      icon: icon,
                      preview: session.previews[id],
                      selected: session.activeId == id,
                      isDefault: session.isDefaultWindow(id),
                      onDefault: () => session.setDefaultWindow(id),
                      onSelect: () {
                        session.activate(id);
                        Navigator.pop(dialog);
                      },
                      onClose:
                          id == null ||
                              session.windows
                                  .firstWhere((w) => w.id == id)
                                  .split
                          ? null
                          : () => session.close(id),
                    );
                return AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(dialog)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeInOutCubic,
                  height: panelHeight,
                  child: Column(
                    children: [
                      ExplorerDialogHeader(
                        title: WindowPanelTabs(
                          windows: session.count,
                          clipboard: files.length,
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            Column(
                              children: [
                                Expanded(
                                  child: GridView.count(
                                    padding: const EdgeInsets.all(12),
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: .90,
                                    children: [
                                      preview(
                                        null,
                                        'Homepage',
                                        Icons.home_outlined,
                                      ),
                                      for (final w in session.windows)
                                        preview(w.id, w.label, w.icon),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () async {
                                          final splitOpened =
                                              await showNewExplorerWindow(
                                                dialog,
                                              );
                                          if (splitOpened && dialog.mounted) {
                                            Navigator.pop(dialog);
                                          }
                                        },
                                        icon: const Icon(Icons.add),
                                        label: const Text('New'),
                                      ),
                                      TextButton(
                                        onPressed: session.closeOthers,
                                        child: const Text('Close others'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            files.isEmpty
                                ? const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.content_paste_outlined,
                                          size: 40,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 12),
                                        Text('Clipboard is empty'),
                                      ],
                                    ),
                                  )
                                : Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          session.clipboardMove?.call() == true
                                              ? 'Ready to move'
                                              : 'Ready to copy',
                                        ),
                                      ),
                                      Expanded(
                                        child: ListView(
                                          children: [
                                            for (final path in files)
                                              ListTile(
                                                leading: const Icon(
                                                  Icons
                                                      .insert_drive_file_outlined,
                                                  color: primaryBlue,
                                                ),
                                                title: Text(baseName(path)),
                                                subtitle: Text(
                                                  path,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            TextButton(
                                              onPressed: session.clearClipboard,
                                              child: const Text('Clear'),
                                            ),
                                            const Spacer(),
                                            FilledButton(
                                              onPressed: () {
                                                final paste =
                                                    session.pasteActions[session
                                                        .activeId];
                                                Navigator.pop(dialog);
                                                if (paste != null) {
                                                  paste();
                                                } else {
                                                  session.open(session.root);
                                                }
                                              },
                                              child: Text(
                                                session.pasteActions
                                                        .containsKey(
                                                          session.activeId,
                                                        )
                                                    ? 'Paste here'
                                                    : 'Choose destination',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
