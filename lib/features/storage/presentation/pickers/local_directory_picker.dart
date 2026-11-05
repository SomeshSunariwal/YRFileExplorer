import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

Future<String?> chooseLocalDirectory(
  BuildContext context, {
  required String initialPath,
  bool hidden = false,
}) {
  var destination = initialPath.startsWith('/')
      ? initialPath
      : '/storage/emulated/0';
  Future<List<Json>> listing = Native.rows('list', {
    'path': destination,
    'hidden': hidden,
  });
  return showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => ExplorerDialog(
        title: const Text('Select folder'),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        content: SizedBox(
          width: 320,
          height: 360,
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Parent folder',
                    onPressed:
                        !ExplorerWorkspaceSession.instance.containsStoragePath(
                          parentPath(destination),
                        )
                        ? null
                        : () => update(() {
                            destination = parentPath(destination);
                            listing = Native.rows('list', {
                              'path': destination,
                              'hidden': hidden,
                            });
                          }),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  Expanded(
                    child: Text(
                      destination,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: FutureBuilder<List<Json>>(
                  future: listing,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final folders = snapshot.data!
                        .where((entry) => entry['directory'] == true)
                        .toList();
                    return ListView(
                      children: [
                        for (final folder in folders)
                          ListTile(
                            leading: FileGlyph(folder, size: 32),
                            title: Text(folder['name']),
                            onTap: () => update(() {
                              destination = folder['path'];
                              listing = Native.rows('list', {
                                'path': destination,
                                'hidden': hidden,
                              });
                            }),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, destination),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}
