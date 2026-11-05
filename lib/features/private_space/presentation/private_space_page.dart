import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/core/utils/file_sort.dart';
import 'package:yr_file_explorer/features/storage/presentation/pickers/local_directory_picker.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/dialogs/operation_progress_dialog.dart';
import 'package:yr_file_explorer/shared/dialogs/view_menu.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';
import 'package:yr_file_explorer/shared/widgets/selection_drag_area.dart';

class PrivateSpacePage extends StatefulWidget {
  final AppSettings settings;
  final int windowId;
  const PrivateSpacePage({
    super.key,
    required this.settings,
    required this.windowId,
  });
  @override
  State<PrivateSpacePage> createState() => _PrivateSpacePageState();
}

class _PrivateSpacePageState extends State<PrivateSpacePage>
    with WidgetsBindingObserver {
  final session = ExplorerWorkspaceSession.instance;
  final selected = <String>{};
  final trail = <Json>[];
  List<Json> rows = [];
  List<String> copied = [];
  bool unlocked = false, unlocking = false, busy = false, cut = false;
  int generation = 0;
  String? error;
  StreamSubscription<Json>? events;
  bool covered = false;
  String get parent => trail.lastOrNull?['id'] ?? '';
  bool get active => session.activeId == widget.windowId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(tabChanged);
    events = Native.events.listen((event) {
      if (event['type'] == 'privateLocked' && mounted) {
        if (active) Navigator.of(context).popUntil((route) => route.isFirst);
        lock(notifyNative: false);
      }
    });
  }

  void tabChanged() {
    if (!active) {
      if (unlocked || unlocking) {
        lock();
      } else {
        Native.call('privateShield', {'enabled': false});
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !unlocking) {
      setState(() => covered = true);
    } else if (state == AppLifecycleState.resumed && unlocked) {
      Native.call<bool>('privateStatus').then((allowed) {
        if (!mounted) return;
        if (allowed != true) {
          lock(notifyNative: false);
        } else {
          setState(() => covered = false);
        }
      });
    }
  }

  void lock({bool notifyNative = true}) {
    generation++;
    if (mounted) {
      setState(() {
        unlocked = false;
        unlocking = false;
        rows = [];
        selected.clear();
        copied = [];
        trail.clear();
      });
    }
    if (notifyNative) Native.call('privateLock');
    Native.call('privateShield', {'enabled': active});
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(tabChanged);
    events?.cancel();
    if (unlocked) {
      Native.call('privateLock');
    }
    Native.call('privateShield', {'enabled': false});
    super.dispose();
  }

  Future<void> unlock() async {
    final request = ++generation;
    setState(() {
      unlocking = true;
      error = null;
    });
    try {
      await Native.call('privateUnlock');
      if (!mounted || request != generation || !active) return;
      setState(() {
        unlocking = false;
        unlocked = true;
        covered = false;
      });
      await load();
    } catch (e) {
      if (mounted && request == generation) {
        setState(() {
          unlocking = false;
          error = e.toString();
        });
      }
    }
  }

  Future<void> load() async {
    final request = generation;
    try {
      final items = await Native.rows('privateList', {'id': parent});
      if (!mounted || request != generation || !active) return;
      setState(() {
        rows = sortedFileEntries(
          items,
          sort: widget.settings.sort,
          descending: widget.settings.descending,
        );
        selected.removeWhere((id) => !rows.any((row) => row['id'] == id));
      });
    } catch (e) {
      if (mounted && request == generation) {
        lock();
        setState(() => error = e.toString());
      }
    }
  }

  void back() {
    if (selected.isNotEmpty) {
      setState(selected.clear);
      return;
    }
    if (trail.isNotEmpty) {
      setState(() => trail.removeLast());
      load();
      return;
    }
    lock();
    session.activate(null);
  }

  Future<void> operate(String name, List<Json> picks) async {
    if (busy || !unlocked) return;
    final ids = picks.map((e) => e['id'] as String).toList();
    try {
      if (name == 'Copy' || name == 'Cut') {
        setState(() {
          copied = ids;
          cut = name == 'Cut';
          selected.clear();
        });
        return;
      }
      if (name == 'Properties') {
        final e = picks.single;
        await showDialog<void>(
          context: context,
          builder: (_) => ExplorerDialog(
            title: const Text('Properties'),
            content: Text(
              '${e['name']}\n${sizeLabel(e['size'])}\n${listDateTimeLabel(e['modified'])}\nEncrypted in Private Space',
            ),
          ),
        );
        return;
      }
      if (name == 'Rename') {
        final value = await askText(
          context,
          'Rename',
          initial: picks.single['name'],
        );
        if (value == null) return;
        await Native.call('privateRename', {'id': ids.single, 'name': value});
        await load();
        return;
      }
      String? destination;
      if (name == 'Remove from Private Space' || name == 'Copy to') {
        if (!await confirm(
          context,
          name,
          'These items will be readable outside Private Space in the folder you choose.',
          action: 'Continue',
        )) {
          return;
        }
        if (!mounted) return;
        destination = await chooseLocalDirectory(
          context,
          initialPath: session.root,
        );
        if (destination == null) return;
      } else if (name == 'Delete') {
        if (!await confirm(
          context,
          'Delete private items?',
          'This permanently deletes ${ids.length} selected items. Private items do not use the Recycle Bin.',
          action: 'Delete',
        )) {
          return;
        }
      }
      if (!mounted || !unlocked) return;
      setState(() => busy = true);
      await runFileOperation(
        context,
        name == 'Delete'
            ? 'Deleting private files…'
            : 'Processing private files…',
        () =>
            Native.call(name == 'Delete' ? 'privateDelete' : 'privateExport', {
              'ids': ids,
              'destination': ?destination,
              'move': name == 'Remove from Private Space',
            }),
      );
      if (mounted && unlocked) {
        selected.clear();
        await load();
      }
    } catch (e) {
      if (mounted && unlocked) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Json e) async {
    if (selected.isNotEmpty) {
      setState(
        () => selected.contains(e['id'])
            ? selected.remove(e['id'])
            : selected.add(e['id']),
      );
      return;
    }
    if (e['directory'] == true) {
      setState(() => trail.add(e));
      await load();
      return;
    }
    final request = generation;
    try {
      final file = await Native.call<String>('privatePreview', {'id': e['id']});
      if (!mounted || request != generation || file == null) return;
      if (e['category'] == 'Images') {
        await Navigator.push(
          context,
          ExplorerPageRoute<void>(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                title: Text(e['name']),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              body: Center(
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 5,
                  child: Image.file(File(file), fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        );
      } else if (e['category'] == 'Videos' ||
          e['category'] == 'Music' ||
          file.toLowerCase().endsWith('.pdf')) {
        await Native.call('open', {'path': file});
      } else {
        if ((e['size'] as num) > 1024 * 1024 ||
            !RegExp(
              r'\.(txt|md|json|xml|csv|log|yaml|yml)$',
              caseSensitive: false,
            ).hasMatch(file)) {
          throw Exception(
            'Move this file out of Private Space to open it with another app.',
          );
        }
        final content = await File(file).readAsString();
        if (!mounted || request != generation) return;
        await showDialog<void>(
          context: context,
          builder: (_) => ExplorerDialog(
            title: Text(e['name']),
            content: SingleChildScrollView(child: SelectableText(content)),
          ),
        );
      }
    } catch (e) {
      if (mounted && unlocked) showError(context, e);
    }
  }

  Future<void> more(List<Json> picks) async {
    final name = await showExplorerActionMenu(context, [
      'Copy',
      'Cut',
      'Copy to',
      if (picks.length == 1) ...['Rename', 'Properties'],
      'Remove from Private Space',
      'Delete',
    ]);
    if (name != null && mounted) await operate(name, picks);
  }

  Future<void> createFolder() async {
    final name = await askText(context, 'New private folder');
    if (name == null || !mounted || !unlocked) return;
    try {
      await Native.call('privateCreate', {'parent': parent, 'name': name});
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> paste() async {
    try {
      await Native.call('privatePaste', {
        'parent': parent,
        'ids': copied,
        'move': cut,
      });
      if (cut) copied = [];
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void view() => showExplorerViewMenu(
    context,
    mode: widget.settings.viewMode,
    sort: widget.settings.sort,
    descending: widget.settings.descending,
    sorts: const ['Name', 'Type', 'Size', 'Modified'],
    groupBy: 'None',
    groupDescending: false,
    onGroupingChanged: (_, _) {},
    onChanged: (mode, sort, descending) {
      widget.settings.viewMode = mode;
      widget.settings.grid = mode.endsWith('Icon');
      widget.settings.sort = sort;
      widget.settings.descending = descending;
      widget.settings.save();
      load();
    },
  );
  @override
  Widget build(BuildContext context) {
    final picks = rows.where((row) => selected.contains(row['id'])).toList();
    Widget action(IconData icon, String label, VoidCallback tap) =>
        ExplorerAction(icon: icon, label: label, enabled: !busy, onTap: tap);
    Widget tile(Json e) => SelectionDragItem(
      id: e['id'],
      child: widget.settings.grid
          ? InkWell(
              onTap: () => open(e),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: selected.contains(e['id'])
                      ? primaryBlue.withValues(alpha: .12)
                      : null,
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(child: Center(child: FileGlyph(e, size: 52))),
                        const SizedBox(height: 6),
                        Text(
                          e['name'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    if (selected.isNotEmpty)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Icon(
                          selected.contains(e['id'])
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 16,
                          color: primaryBlue,
                        ),
                      ),
                  ],
                ),
              ),
            )
          : ListTile(
              onTap: () => open(e),
              selected: selected.contains(e['id']),
              leading: SizedBox.square(
                dimension: 40,
                child: Center(child: FileGlyph(e, size: 32)),
              ),
              title: Text(
                e['name'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${sizeLabel(e['size'])} · ${listDateTimeLabel(e['modified'])}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: SizedBox.square(
                dimension: 40,
                child: selected.isNotEmpty
                    ? Icon(
                        selected.contains(e['id'])
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: primaryBlue,
                        size: 18,
                      )
                    : null,
              ),
            ),
    );
    return ExplorerPane(
      settings: widget.settings,
      windowId: widget.windowId,
      busy: busy,
      onBack: back,
      title: Text(
        selected.isNotEmpty
            ? '${selected.length}/${rows.length}'
            : trail.lastOrNull?['name'] ?? 'Private Space',
      ),
      selecting: selected.isNotEmpty,
      onSelectAll: () => setState(
        () => selected.addAll(rows.map((row) => row['id'] as String)),
      ),
      onClearSelection: () => setState(selected.clear),
      actions: !unlocked
          ? [
              action(Icons.lock_open, 'Unlock', unlock),
              action(
                Icons.filter_none,
                'Windows',
                () => showExplorerWindows(context),
              ),
            ]
          : selected.isNotEmpty
          ? [
              action(Icons.copy_outlined, 'Copy', () => operate('Copy', picks)),
              action(Icons.content_cut, 'Cut', () => operate('Cut', picks)),
              action(
                Icons.delete_outline,
                'Delete',
                () => operate('Delete', picks),
              ),
              action(
                Icons.lock_open_outlined,
                'Remove',
                () => operate('Remove from Private Space', picks),
              ),
              action(Icons.more_horiz, 'More', () => more(picks)),
            ]
          : [
              action(Icons.create_new_folder_outlined, 'New', createFolder),
              if (copied.isNotEmpty)
                action(Icons.content_paste, 'Paste', paste)
              else
                action(Icons.refresh, 'Refresh', load),
              action(Icons.grid_view, 'View', view),
              action(Icons.lock_outline, 'Lock', lock),
              action(
                Icons.filter_none,
                'Windows',
                () => showExplorerWindows(context),
              ),
            ],
      body: !unlocked || covered
          ? EmptyState(
              icon: Icons.lock_outline,
              title: 'Private Space is locked',
              message: error ?? 'Unlock with your device screen lock or fingerprint.\nFiles are encrypted and excluded from backups.\nRemoving the app or resetting device security can make them unrecoverable.',
              action: FilledButton.icon(
                onPressed: unlocking ? null : unlock,
                icon: const Icon(Icons.fingerprint),
                label: Text(unlocking ? 'Unlocking…' : 'Unlock'),
              ),
            )
          : rows.isEmpty
          ? const EmptyState(
              icon: Icons.lock_outline,
              title: 'No private files',
              message: 'Select files or folders in Device, then choose Move to Private Space.',
            )
          : SelectionDragArea(
              selected: selected,
              enabled: !busy,
              onSelection: (id, value) => setState(() {
                value ? selected.add(id) : selected.remove(id);
              }),
              child: LayoutBuilder(
                builder: (context, constraints) => widget.settings.grid
                    ? GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          12,
                          12,
                          ExplorerBottomBar.contentBottomPadding(context),
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: (constraints.maxWidth / 100)
                              .floor()
                              .clamp(2, 8),
                          mainAxisExtent: 112,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (_, i) => tile(rows[i]),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: ExplorerBottomBar.contentBottomPadding(
                            context,
                          ),
                        ),
                        itemCount: rows.length,
                        itemBuilder: (_, i) => tile(rows[i]),
                      ),
              ),
            ),
    );
  }
}
