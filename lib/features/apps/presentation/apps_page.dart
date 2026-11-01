import 'dart:io';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/dialogs/view_menu.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';

class AppsPage extends StatefulWidget {
  final AppSettings settings;
  final int? windowId;
  const AppsPage({super.key, required this.settings, this.windowId});
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> with WidgetsBindingObserver {
  List<Json> apps = [];
  final selected = <String>{};
  final search = TextEditingController();
  String filter = 'User Apps', sort = 'Name', viewMode = 'Medium Icon';
  String? error;
  bool loading = true,
      searching = false,
      busy = false,
      grid = true,
      descending = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) load();
  }

  String key(Json app) => app['path'];
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await Native.rows(
        filter == 'All apks' || filter == 'Backed-up Apps'
            ? 'apkFiles'
            : 'apps',
        {
          'system': true,
          'path': filter == 'Backed-up Apps'
              ? '${ExplorerWorkspaceSession.instance.root}/backups/apps'
              : ExplorerWorkspaceSession.instance.root,
        },
      );
      if (mounted) {
        setState(() {
          apps = rows;
          selected.removeWhere((p) => !rows.any((a) => key(a) == p));
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  List<Json> get rows {
    final result = apps.where((a) {
      if (filter == 'User Apps' && a['system'] == true) return false;
      if (filter == 'System Apps' && a['system'] != true) return false;
      if (filter == 'Installed on phone' && a['external'] == true) return false;
      if (filter == 'Installed in sdcard' && a['external'] != true) {
        return false;
      }
      return '${a['name']} ${a['package']}'.toLowerCase().contains(
        search.text.toLowerCase(),
      );
    }).toList();
    result.sort((a, b) {
      final v = switch (sort) {
        'Size' => (a['size'] as num).compareTo(b['size'] as num),
        'Installed' => (a['installed'] as num? ?? 0).compareTo(
          b['installed'] as num? ?? 0,
        ),
        _ => a['name'].toString().toLowerCase().compareTo(
          b['name'].toString().toLowerCase(),
        ),
      };
      return descending ? -v : v;
    });
    return result;
  }

  void toggle(Json a) => setState(() {
    selected.contains(key(a)) ? selected.remove(key(a)) : selected.add(key(a));
  });
  Future<void> chooseFilter() async {
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Center(child: Text('History')),
        children: [
          for (final name in [
            'User Apps',
            'System Apps',
            'Installed on phone',
            'Installed in sdcard',
            'Backed-up Apps',
            'All apks',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, name),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(
                      name == filter
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: primaryBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(name),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      filter = value;
      selected.clear();
    });
    await load();
  }

  Future<void> run(String action, List<Json> picks) async {
    if (picks.isEmpty || busy) return;
    if (action == 'Properties') {
      final a = picks.first;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(a['name']),
          content: SingleChildScrollView(
            child: SelectableText(
              'Package: ${a['package']}\nVersion: ${a['version']}\nSize: ${sizeLabel(a['size'])}\nInstalled: ${dateLabel(a['installed'] ?? 0)}\n${a['path']}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
            if (a['backup'] != true)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialog);
                  Native.call('appSettings', {'package': a['package']});
                },
                child: const Text('App info'),
              ),
          ],
        ),
      );
      return;
    }
    if (action == 'Uninstall' &&
        !await confirm(
          context,
          'Uninstall applications?',
          'Android will ask you to confirm each selected application.',
          action: 'Continue',
        )) {
      return;
    }
    setState(() => busy = true);
    try {
      final exports = <String>[];
      for (final a in picks) {
        switch (action) {
          case 'Open':
            await Native.call(a['backup'] == true ? 'open' : 'launchApp', {
              'package': a['package'],
              'path': a['path'],
            });
          case 'Backup':
            if (a['backup'] == true) continue;
            exports.add(
              (await Native.call<String>('backupApp', {
                'package': a['package'],
                'destination':
                    '${ExplorerWorkspaceSession.instance.root}/backups/apps',
              }))!,
            );
          case 'Share':
          case 'Send':
            if (a['backup'] == true) {
              exports.add(a['path']);
            } else {
              exports.addAll(
                List<String>.from(
                  (await Native.call<List>('exportApp', {
                    'package': a['package'],
                  }))!,
                ),
              );
            }
          case 'Uninstall':
            if (a['backup'] != true) {
              await Native.call('uninstall', {'package': a['package']});
            }
          case 'Add to desktop':
            await Native.call('pinApp', {'package': a['package']});
          case 'App info':
            await Native.call('appSettings', {'package': a['package']});
        }
      }
      if (action == 'Share' || action == 'Send') {
        await Native.call('share', {'paths': exports});
      }
      if (action == 'Backup' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${exports.length} backed up to backups/apps'),
          ),
        );
      }
      if (mounted) setState(() => selected.clear());
      if (action == 'Uninstall') await load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> more(List<Json> picks) async {
    final action = await showExplorerActionMenu(context, [
      'Properties',
      if (picks.length == 1 && picks.first['backup'] != true) ...[
        'Open',
        'App info',
        'Add to desktop',
      ],
    ]);
    if (action != null && mounted) await run(action, picks);
  }

  Future<void> view() => showExplorerViewMenu(
    context,
    mode: viewMode,
    sort: sort,
    descending: descending,
    sorts: const ['Name', 'Size', 'Installed'],
    onChanged: (mode, nextSort, nextDescending) => setState(() {
      viewMode = mode;
      grid = mode.endsWith('Icon');
      sort = nextSort;
      descending = nextDescending;
    }),
  );
  Widget icon(Json a, {double size = 44}) => a['icon'] is String
      ? Image.file(
          File(a['icon']),
          width: size,
          height: size,
          errorBuilder: (_, _, _) =>
              Icon(Icons.android, color: primaryBlue, size: size),
        )
      : Icon(Icons.android, color: primaryBlue, size: size);
  @override
  Widget build(BuildContext context) {
    final visible = rows;
    final picks = apps.where((a) => selected.contains(key(a))).toList();
    Widget action(IconData icon, String label, VoidCallback tap) =>
        ExplorerAction(icon: icon, label: label, onTap: busy ? () {} : tap);
    return ExplorerPane(
      onActivate: load,
      settings: widget.settings,
      windowId: widget.windowId,
      selecting: selected.isNotEmpty,
      interceptBack: searching,
      onBack: selected.isNotEmpty
          ? () => setState(() => selected.clear())
          : searching
          ? () => setState(() {
              search.clear();
              searching = false;
            })
          : null,
      title: Text(
        selected.isNotEmpty ? '${selected.length}/${visible.length}' : filter,
      ),
      onTitle: selected.isEmpty ? chooseFilter : null,
      actions: selected.isEmpty
          ? [
              ExplorerAction(
                icon: Icons.add,
                label: 'New',
                enabled: false,
                onTap: () {},
              ),
              action(
                Icons.search,
                'Search',
                () => setState(() {
                  if (searching) search.clear();
                  searching = !searching;
                }),
              ),
              action(Icons.refresh, 'Refresh', load),
              action(Icons.grid_view, 'View', view),
              action(
                Icons.filter_none,
                'Windows',
                () => showExplorerWindows(context),
              ),
            ]
          : [
              action(
                Icons.delete_outline,
                'Uninstall',
                () => run('Uninstall', picks),
              ),
              action(
                Icons.backup_outlined,
                'Backup',
                () => run('Backup', picks),
              ),
              action(Icons.share_outlined, 'Share', () => run('Share', picks)),
              action(Icons.send_outlined, 'Send', () => run('Send', picks)),
              action(Icons.more_horiz, 'More', () => more(picks)),
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
                  hintText: 'Search applications',
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
          if (selected.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => selected.addAll(visible.map(key))),
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: () => setState(() => selected.clear()),
                  child: const Text('Clear selection'),
                ),
              ],
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? EmptyState(
                    title: 'Cannot load applications',
                    message: error!,
                    action: FilledButton(
                      onPressed: load,
                      child: const Text('Retry'),
                    ),
                  )
                : visible.isEmpty
                ? const EmptyState(
                    icon: Icons.android,
                    title: 'No applications',
                    message: 'Try another app category or search.',
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: grid
                        ? GridView.builder(
                            padding: const EdgeInsets.all(10),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: explorerGridColumns(viewMode),
                                  childAspectRatio: .83,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final a = visible[i];
                              return InkWell(
                                onLongPress: () => toggle(a),
                                onTap: () => selected.isEmpty
                                    ? run('Open', [a])
                                    : toggle(a),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: selected.contains(key(a))
                                        ? primaryBlue.withValues(alpha: .12)
                                        : null,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          icon(
                                            a,
                                            size: explorerGlyphSize(viewMode),
                                          ),
                                          if (selected.contains(key(a)))
                                            const Positioned(
                                              right: -4,
                                              bottom: -4,
                                              child: Icon(
                                                Icons.check_circle,
                                                color: primaryBlue,
                                                size: 19,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 32,
                                        child: Text(
                                          a['name'],
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            height: 1.25,
                                          ),
                                        ),
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
                              final a = visible[i];
                              return ListTile(
                                selected: selected.contains(key(a)),
                                dense: viewMode.startsWith('Small'),
                                leading: icon(a, size: 38),
                                title: Text(a['name']),
                                subtitle: viewMode.endsWith('Detail')
                                    ? Text(
                                        '${a['version']} · ${sizeLabel(a['size'])}',
                                        style: const TextStyle(fontSize: 11),
                                      )
                                    : null,
                                onLongPress: () => toggle(a),
                                onTap: () => selected.isEmpty
                                    ? run('Open', [a])
                                    : toggle(a),
                                trailing: IconButton(
                                  tooltip: 'More',
                                  onPressed: () => more([a]),
                                  icon: const Icon(Icons.more_vert),
                                ),
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
