import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
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
import 'package:yr_file_explorer/shared/dialogs/view_menu.dart';
import 'package:yr_file_explorer/shared/widgets/breadcrumbs.dart';
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
  late bool beganAtServer;
  int loadVersion = 0;
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
    beganAtServer =
        profile['protocol'] == 'SMB' &&
        (profile['share']?.toString().isEmpty ?? true);
    if (profile['protocol'] != 'Bluetooth' &&
        profile['anonymous'] != true &&
        (profile['username']?.toString().isNotEmpty ?? false) &&
        !profile.containsKey('password')) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final password = await askText(
          context,
          'Connect to ${profile['name']}',
          label: 'Password',
          secret: true,
        );
        if (!mounted) return;
        if (password == null) {
          setState(() {
            loading = false;
            error = 'Connection cancelled';
          });
          return;
        }
        profile['password'] = password;
        load();
      });
    } else {
      load();
    }
  }

  Future<dynamic> request(
    String action, {
    String? remote,
    String? local,
    String? destination,
    bool directory = false,
    int retry = 0,
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
      if (retry >= 1) throw Exception('Bluetooth authentication failed');
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
        retry: retry + 1,
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
      if (retry >= 1) throw Exception('The server key could not be verified');
      profile['fingerprint'] = result['fingerprint'];
      final window = ExplorerWorkspaceSession.instance.windows
          .where((w) => w.id == widget.windowId)
          .firstOrNull;
      if (window?.profile != null) {
        window!.profile!['fingerprint'] = result['fingerprint'];
      }
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
        retry: retry + 1,
      );
    }
    return result;
  }

  Future<void> load() async {
    final version = ++loadVersion;
    if (widget.windowId != null) {
      final window = ExplorerWorkspaceSession.instance.windows
          .where((w) => w.id == widget.windowId)
          .firstOrNull;
      window?.profile?.addAll(profile);
      ExplorerWorkspaceSession.instance.updatePath(widget.windowId!, path);
    }
    setState(() {
      loading = rows.isEmpty;
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
      if (mounted && version == loadVersion) {
        setState(() {
          rows = r;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && version == loadVersion) {
        setState(() {
          loading = false;
          error = e is PlatformException ? e.message : e.toString();
        });
      }
    }
  }

  bool get shares =>
      profile['protocol'] == 'SMB' &&
      (profile['share']?.toString().isEmpty ?? true);
  String join(String name, [String? folder]) {
    final item = baseName(name);
    final encoded = profile['protocol'] == 'WebDAV'
        ? Uri.encodeComponent(item)
        : item;
    return '${(folder ?? path).replaceAll(RegExp(r'[/\\]$'), '')}/$encoded';
  }

  List<(String, String)> get breadcrumbs {
    final parts = path
        .replaceAll('\\', '/')
        .split('/')
        .where((p) => p.isNotEmpty);
    var current = '';
    return [
      (
        profile['share']?.toString().isNotEmpty == true
            ? profile['share'].toString()
            : profile['name']?.toString() ?? profile['host'].toString(),
        '/',
      ),
      for (final part in parts)
        (Uri.decodeComponent(part), current = '$current/$part'),
    ];
  }

  Future<void> download(Json e, {bool showFailure = true}) async {
    try {
      final target =
          '${ExplorerWorkspaceSession.instance.root}/Download/${baseName(e['name'])}';
      if (showFailure) setState(() => busy = true);
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
      if (!showFailure) rethrow;
      if (mounted) showError(context, e);
    } finally {
      if (mounted && showFailure) setState(() => busy = false);
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
    String? destinationFolder;
    if (action == 'Copy to' || action == 'Move to') {
      destinationFolder = await askText(
        context,
        action,
        label: 'Destination folder',
        initial: path,
      );
      if (destinationFolder == null || destinationFolder.trim().isEmpty) return;
      destinationFolder = destinationFolder.trim();
      if (!destinationFolder.startsWith('/')) {
        if (mounted) {
          showError(context, Exception('Enter an absolute remote folder path'));
        }
        return;
      }
    }
    if (!mounted) return;
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
            await download(e, showFailure: false);
          case 'Copy to':
          case 'Move to':
            await request(
              action == 'Copy to' ? 'copy' : 'rename',
              remote: e['path'],
              destination: join(e['name'], destinationFolder),
              directory: e['directory'] == true,
            );
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
    if (target == path) return;
    final seen = history.lastIndexOf(path);
    if (seen >= 0) history.removeRange(seen, history.length);
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
    if (searching) {
      search.clear();
      setState(() => searching = false);
      return;
    }
    if (history.isNotEmpty) {
      path = history.removeLast();
      load();
    } else if (beganAtServer && !shares) {
      profile['share'] = '';
      path = '/';
      selected.clear();
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
        if (beganAtServer && !shares)
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialog);
              profile['share'] = '';
              path = '/';
              history.clear();
              selected.clear();
              load();
            },
            child: const Text('Shared folders'),
          ),
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
    loadVersion++;
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
      busy: busy,
      settings: widget.settings,
      windowId: widget.windowId,
      selecting: selected.isNotEmpty,
      onBack: back,
      onTitle: locations,
      title: selected.isNotEmpty
          ? Text('${selected.length}/${rows.length}')
          : ExplorerBreadcrumbs(
              entries: breadcrumbs,
              onNavigate: navigate,
              onCurrent: locations,
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
              tool(Icons.info_outline, 'More', () async {
                final choice = await showExplorerActionMenu(context, [
                  'Properties',
                  if (profile['protocol'] != 'Bluetooth') ...[
                    'Copy to',
                    'Move to',
                  ],
                ]);
                if (choice != null && mounted) await action(choice, picks);
              }),
              tool(
                Icons.filter_none,
                'Windows',
                () => showExplorerWindows(context),
              ),
            ]
          : [
              ExplorerAction(
                icon: Icons.add,
                label: 'New',
                enabled: !busy && !shares,
                onTap: create,
              ),
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
                onPressed: busy || shares ? null : upload,
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
                            padding: EdgeInsets.fromLTRB(
                              10,
                              10,
                              10,
                              ExplorerBottomBar.contentBottomPadding(context),
                            ),
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
                                onLongPress: shares ? null : () => toggle(e),
                                onTap: () => selected.isNotEmpty
                                    ? toggle(e)
                                    : e['share'] != null
                                    ? setState(() {
                                        profile['share'] = e['share'];
                                        path = '/';
                                        selected.clear();
                                        load();
                                      })
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
                            padding: EdgeInsets.only(
                              bottom: ExplorerBottomBar.contentBottomPadding(
                                context,
                              ),
                            ),
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
                                onLongPress: shares ? null : () => toggle(e),
                                onTap: () => selected.isNotEmpty
                                    ? toggle(e)
                                    : e['share'] != null
                                    ? setState(() {
                                        profile['share'] = e['share'];
                                        path = '/';
                                        selected.clear();
                                        load();
                                      })
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
