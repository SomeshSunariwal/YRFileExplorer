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
  List<Json> volumes = const [],
  String? defaultPath,
}) {
  var destination = initialPath.startsWith('/')
      ? initialPath
      : '/storage/emulated/0';
  Future<List<Json>> listFolders(String path) =>
      Native.rows('list', {'path': path, 'hidden': hidden});
  var listing = listFolders(destination);
  void navigate(StateSetter update, String path) => update(() {
    destination = path;
    listing = listFolders(path);
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
                        !(volumes.isEmpty
                            ? ExplorerWorkspaceSession.instance
                                  .containsStoragePath(parentPath(destination))
                            : volumes.any((volume) {
                                final root = volume['path'] as String;
                                final parent = parentPath(destination);
                                return parent == root ||
                                    parent.startsWith('$root/');
                              }))
                        ? null
                        : () => navigate(update, parentPath(destination)),
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
                  if (volumes.length > 1)
                    PopupMenuButton<String>(
                      tooltip: 'Switch storage',
                      icon: const Icon(Icons.sd_storage_outlined),
                      onSelected: (path) => navigate(update, path),
                      itemBuilder: (_) => [
                        for (final volume in volumes)
                          PopupMenuItem(
                            value: volume['path'] as String,
                            child: Text(volume['name'] as String),
                          ),
                      ],
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
                    return ListView.builder(
                      itemCount: folders.length,
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return ListTile(
                          leading: FileGlyph(folder, size: 32),
                          title: Text(folder['name']),
                          onTap: () => navigate(update, folder['path']),
                        );
                      },
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
          if (defaultPath != null)
            TextButton(
              onPressed: () => Navigator.pop(dialog, defaultPath),
              child: const Text('Use default'),
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
