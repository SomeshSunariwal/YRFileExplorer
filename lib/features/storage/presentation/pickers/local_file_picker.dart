import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

Future<List<String>?> pickLocalFiles(
  BuildContext context, {
  required String root,
  List<String> initial = const [],
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => _LocalFiles(root: root, initial: initial),
);

class _LocalFiles extends StatefulWidget {
  final String root;
  final List<String> initial;
  const _LocalFiles({required this.root, required this.initial});
  @override
  State<_LocalFiles> createState() => _LocalFilesState();
}

class _LocalFilesState extends State<_LocalFiles> {
  late String path;
  late Future<List<Json>> listing;
  final selected = <String>{};
  @override
  void initState() {
    super.initState();
    path = widget.root;
    selected.addAll(widget.initial);
    listing = Native.rows('list', {'path': path, 'hidden': false});
  }

  void go(String value) => setState(() {
    if (!ExplorerWorkspaceSession.instance.containsStoragePath(value)) return;
    path = value;
    listing = Native.rows('list', {'path': path, 'hidden': false});
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Upload (${selected.length})'),
    contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    content: SizedBox(
      width: 440,
      height: MediaQuery.sizeOf(context).height * .58,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Parent folder',
                onPressed:
                    !ExplorerWorkspaceSession.instance.containsStoragePath(
                      parentPath(path),
                    )
                    ? null
                    : () => go(parentPath(path)),
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                child: Text(
                  path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Internal storage',
                onPressed: () => go(widget.root),
                icon: const Icon(Icons.phone_android_outlined),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<Json>>(
              future: listing,
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = List<Json>.of(snapshot.data!)
                  ..sort(
                    (a, b) => a['directory'] != b['directory']
                        ? (a['directory'] == true ? -1 : 1)
                        : a['name'].toString().toLowerCase().compareTo(
                            b['name'].toString().toLowerCase(),
                          ),
                  );
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final e = rows[i];
                    void toggle() => setState(() {
                      selected.contains(e['path'])
                          ? selected.remove(e['path'])
                          : selected.add(e['path']);
                    });
                    return ListTile(
                      leading: FileGlyph(e, size: 28),
                      title: Text(
                        e['name'],
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        e['directory'] == true
                            ? 'Folder'
                            : sizeLabel(e['size']),
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: e['directory'] == true
                          ? () => go(e['path'])
                          : toggle,
                      onLongPress: toggle,
                      trailing: Checkbox(
                        value: selected.contains(e['path']),
                        onChanged: (_) => toggle(),
                      ),
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
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: selected.isEmpty
            ? null
            : () => Navigator.pop(context, selected.toList()),
        child: const Text('Upload'),
      ),
    ],
  );
}
