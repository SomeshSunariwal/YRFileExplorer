import 'package:flutter/material.dart';

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
    builder: (dialog) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          height: MediaQuery.sizeOf(dialog).height * .72,
          child: DefaultTabController(
            length: 2,
            child: AnimatedBuilder(
              animation: session,
              builder: (_, _) {
                final files = session.clipboardItems?.call() ?? <String>[];
                Widget preview(int? id, String label, IconData icon) =>
                    WindowPreviewCard(
                      label: label,
                      icon: icon,
                      preview: session.previews[id],
                      selected: session.activeId == id,
                      isDefault: session.isDefaultWindow(id),
                      locked:
                          id != null &&
                          session.windows.firstWhere((w) => w.id == id).locked,
                      onDefault: () => session.setDefaultWindow(id),
                      onSelect: () {
                        session.activate(id);
                        Navigator.pop(dialog);
                      },
                      onClose: id == null ? null : () => session.close(id),
                    );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${session.count} open windows',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close panel',
                            onPressed: () => Navigator.pop(dialog),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    TabBar(
                      tabs: [
                        Tab(text: 'Windows (${session.count})'),
                        Tab(
                          text: files.isEmpty
                              ? 'Clipboard'
                              : 'Clipboard (${files.length})',
                        ),
                      ],
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
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        showNewExplorerWindow(dialog);
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
                                                overflow: TextOverflow.ellipsis,
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
                                              session.pasteActions.containsKey(
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
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
