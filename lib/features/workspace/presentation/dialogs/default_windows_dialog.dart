import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:flutter/material.dart';

import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

Future<void> showDefaultWindows(BuildContext context) {
  final session = ExplorerWorkspaceSession.instance;
  return showDialog<void>(
    context: context,
    builder: (dialog) => AnimatedBuilder(
      animation: session,
      builder: (_, _) => ExplorerDialog(
        title: const Text('Default windows'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('Open these windows when the app starts.'),
              const SizedBox(height: 12),
              for (final entry in session.defaults)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    entry['kind'] == 'home'
                        ? Icons.home_outlined
                        : Icons.folder_outlined,
                  ),
                  title: Text(
                    entry['kind'] == 'home'
                        ? 'Homepage'
                        : entry['title'] ?? entry['path'] ?? 'Local',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove default',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      session.defaults.remove(entry);
                      session.onSaveDefaults?.call(List.of(session.defaults));
                      session.clipboardChanged();
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              session.saveDefaults();
              Navigator.pop(dialog);
            },
            child: const Text('Use current windows'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}
