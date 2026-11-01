import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/storage/presentation/pickers/local_file_picker.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class RemoteBrowser extends StatefulWidget {
  final int? windowId;
  final Json profile;
  final AppSettings settings;
  final FileClipboard clipboard;
  const RemoteBrowser({
    super.key,
    this.windowId,
    required this.profile,
    required this.settings,
    required this.clipboard,
  });
  @override
  State<RemoteBrowser> createState() => _RemoteBrowserState();
}

class _RemoteBrowserState extends State<RemoteBrowser> {
  late Json profile;
  late String path;
  List<Json> rows = [];
  final history = <String>[];
  bool loading = true, busy = false, grid = true, searching = false;
  final search = TextEditingController();
  final selected = <String>{};
  String? error;
  @override
  void initState() {
    super.initState();
    profile = Map.of(widget.profile);
    path = profile['path'] ?? '/';
    load();
  }

  Future<dynamic> request(
    String action, {
    String? remote,
    String? local,
    String? destination,
    bool directory = false,
  }) async {
    final result = await Native.call('network', {
      ...profile,
      'action': action,
      'path': remote ?? path,
      'local': local ?? '',
      'destination': destination ?? '',
      'directory': directory,
    });
    if (result is Map && result['needsPassword'] == true) {
      if (!mounted) return null;
      final password = await askText(
        context,
        'Bluetooth file access',
        label: 'Password',
        secret: true,
      );
      if (password == null) {
        throw Exception('Bluetooth authentication cancelled');
      }
      profile['password'] = password;
      return request(
        action,
        remote: remote,
        local: local,
        destination: destination,
        directory: directory,
      );
    }
    if (result is Map && result['needsTrust'] == true) {
      if (!mounted) return null;
      final accepted = await confirm(
        context,
        result['changed'] == true
            ? 'Server key has changed'
            : 'Verify SFTP server',
        'Compare this fingerprint with your server before connecting:\n\n${result['fingerprint']}',
        action: 'Trust this key',
      );
      if (!accepted) throw Exception('Server key was not trusted');
      profile['fingerprint'] = result['fingerprint'];
      for (final p in widget.settings.connections) {
        if (p['host'] == profile['host'] &&
            p['port'] == profile['port'] &&
            p['protocol'] == profile['protocol']) {
          p['fingerprint'] = result['fingerprint'];
        }
      }
      await widget.settings.save();
      return request(
        action,
        remote: remote,
        local: local,
        destination: destination,
        directory: directory,
      );
    }
    return result;
  }

  Future<void> load() async {
    if (widget.windowId != null) {
      ExplorerWorkspaceSession.instance.updatePath(widget.windowId!, path);
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = jsonRows(await request('list'));
      r.sort((a, b) {
        if (a['directory'] != b['directory']) {
          return a['directory'] == true ? -1 : 1;
        }
        return a['name'].toString().compareTo(b['name'].toString());
      });
      if (mounted) {
        setState(() {
          rows = r;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e is PlatformException ? e.message : e.toString();
        });
      }
    }
  }

  String join(String name) =>
      '${path.replaceAll(RegExp(r'[/\\]$'), '')}/${baseName(name)}';
  Future<void> download(Json e) async {
    try {
      final target = '/storage/emulated/0/Download/${baseName(e['name'])}';
      setState(() => loading = true);
      await request(
        'get',
        remote: e['path'],
        local: target,
        directory: e['directory'] == true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved $target')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> upload() async {
    final files = await pickLocalFiles(
      context,
      root: ExplorerWorkspaceSession.instance.root,
      initial: widget.clipboard.paths,
    );
    if (files == null || !mounted) return;
    setState(() => busy = true);
    try {
      for (final file in files) {
        await request('put', remote: join(baseName(file)), local: file);
      }
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    final name = await askText(context, 'New folder');
    if (name == null || name.trim().isEmpty) return;
    if (name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      if (mounted) {
        showError(context, Exception('Enter a folder name without slashes'));
      }
      return;
    }
    try {
      setState(() => busy = true);
      await request('mkdir', remote: join(name));
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(String action, List<Json> picks) async {
    if (picks.isEmpty || busy) return;
    if (action == 'Delete' &&
        !await confirm(
          context,
          'Delete remote items?',
          'Permanently remove ${picks.length} selected items from the server?',
          action: 'Delete',
        )) {
      return;
    }
    if (!mounted) return;
    if (action == 'Properties') {
      final e = picks.first;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(e['name']),
          content: SelectableText(
            '${profile['protocol']} · ${profile['host']}\n${e['path']}\n${e['directory'] == true ? 'Folder' : sizeLabel(e['size'])}\n${dateLabel(e['modified'] ?? 0)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    String? rename;
    if (action == 'Rename') {
      rename = await askText(context, 'Rename', initial: picks.first['name']);
      if (rename == null || rename.isEmpty) return;
      if (rename == '.' ||
          rename == '..' ||
          rename.contains('/') ||
          rename.contains('\\')) {
        return;
      }
    }
    setState(() => busy = true);
    try {
      for (final e in picks) {
        switch (action) {
          case 'Download':
            await download(e);
          case 'Delete':
            await request('delete', remote: e['path']);
          case 'Rename':
            await request(
              'rename',
              remote: e['path'],
              destination: join(rename!),
            );
        }
      }
      selected.clear();
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void toggle(Json e) => setState(() {
    selected.contains(e['path'])
        ? selected.remove(e['path'])
        : selected.add(e['path']);
  });
  void navigate(String target) {
    history.add(path);
    path = target;
    selected.clear();
    load();
  }

  void back() {
    if (selected.isNotEmpty) {
      setState(() => selected.clear());
      return;
    }
    if (history.isNotEmpty) {
      path = history.removeLast();
      load();
    } else if (widget.windowId != null) {
      ExplorerWorkspaceSession.instance.activate(null);
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> locations() async => showDialog<void>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: Text(profile['name']),
      children: [
        for (final location in {'/', ...history.reversed, path})
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialog);
              navigate(location);
            },
            child: Text(location),
          ),
      ],
    ),
  );
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = rows
        .where(
          (e) => e['name'].toString().toLowerCase().contains(
            search.text.toLowerCase(),
          ),
        )
        .toList();
    final picks = rows.where((e) => selected.contains(e['path'])).toList();
    Widget tool(IconData icon, String label, VoidCallback tap) =>
        ExplorerAction(icon: icon, label: label, onTap: busy ? () {} : tap);
    return ExplorerPane(
      settings: widget.settings,
      windowId: widget.windowId,
      selecting: selected.isNotEmpty,
      onBack: back,
      onTitle: locations,
      title: Text(
        selected.isNotEmpty
            ? '${selected.length}/${rows.length}'
            : path == '/'
            ? profile['name']
            : baseName(path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: selected.isNotEmpty
          ? [
              tool(
                Icons.download_outlined,
                'Download',
                () => action('Download', picks),
              ),
              tool(
                Icons.edit_outlined,
                'Rename',
                () => action('Rename', picks),
              ),
              tool(
                Icons.delete_outline,
                'Delete',
                () => action('Delete', picks),
              ),
              tool(
                Icons.info_outline,
                'Properties',
                () => action('Properties', picks),
              ),
              tool(
                Icons.filter_none,
                'Windows',
                () => showExplorerWindows(context),
              ),
            ]
          : [
              tool(Icons.add, 'New', create),
              tool(
                Icons.search,
                'Search',
                () => setState(() => searching = !searching),
              ),
              tool(Icons.refresh, 'Refresh', load),
              tool(Icons.grid_view, 'View', () => setState(() => grid = !grid)),
              tool(
                Icons.filter_none,
                'Windows',
                () => showExplorerWindows(context),
              ),
            ],
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (searching)
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search this folder',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Close search',
                    onPressed: () {
                      search.clear();
                      setState(() => searching = false);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Parent folder',
                onPressed: path == '/'
                    ? null
                    : () => navigate(parentPath(path)),
                icon: const Icon(
                  Icons.arrow_upward,
                  size: 20,
                  color: primaryBlue,
                ),
              ),
              Expanded(
                child: Text(
                  '${profile['protocol']} · ${profile['host']} · $path',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              TextButton.icon(
                onPressed: busy ? null : upload,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: const Text('Upload', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? EmptyState(
                    icon: Icons.dns_outlined,
                    title: 'Connection failed',
                    message: error!,
                    action: FilledButton(
                      onPressed: load,
                      child: const Text('Retry'),
                    ),
                  )
                : visible.isEmpty
                ? const EmptyState(
                    title: 'Empty remote folder',
                    message: 'Upload files or create a folder.',
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: grid
                        ? GridView.builder(
                            padding: const EdgeInsets.all(10),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: .82,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final e = visible[i];
                              return InkWell(
                                onLongPress: () => toggle(e),
                                onTap: () => selected.isNotEmpty
                                    ? toggle(e)
                                    : e['directory'] == true
                                    ? navigate(e['path'])
                                    : download(e),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: selected.contains(e['path'])
                                        ? primaryBlue.withValues(alpha: .12)
                                        : null,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      selected.contains(e['path'])
                                          ? const Icon(
                                              Icons.check_circle,
                                              size: 42,
                                              color: primaryBlue,
                                            )
                                          : FileGlyph({
                                              ...e,
                                              'path': '',
                                            }, size: 46),
                                      const SizedBox(height: 8),
                                      Text(
                                        e['name'],
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final e = visible[i];
                              return ListTile(
                                selected: selected.contains(e['path']),
                                leading: FileGlyph({...e, 'path': ''}),
                                title: Text(e['name']),
                                subtitle: Text(
                                  e['directory'] == true
                                      ? 'Folder'
                                      : sizeLabel(e['size']),
                                ),
                                onLongPress: () => toggle(e),
                                onTap: () => selected.isNotEmpty
                                    ? toggle(e)
                                    : e['directory'] == true
                                    ? navigate(e['path'])
                                    : download(e),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
