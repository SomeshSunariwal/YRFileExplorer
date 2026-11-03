import 'package:yr_file_explorer/core/utils/file_sort.dart';
import 'package:yr_file_explorer/shared/dialogs/operation_progress_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class TrashPage extends StatefulWidget {
  final AppSettings settings;
  final int? windowId;
  const TrashPage({super.key, required this.settings, this.windowId});
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Json> rows = [];
  final selected = <String>{};
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool background = false}) async {
    setState(() {
      if (!background) loading = true;
      error = null;
    });
    try {
      final r = foldersFirst(await Native.rows('trash'));
      if (mounted) {
        setState(() {
          rows = r;
          selected.removeWhere((id) => !r.any((e) => e['id'] == id));
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

  void toggle(Json e) => setState(() {
    selected.contains(e['id'])
        ? selected.remove(e['id'])
        : selected.add(e['id']);
  });
  Future<void> operate(String action, List<Json> picks) async {
    if (picks.isEmpty || busy) return;
    if (action == 'delete' &&
        !await confirm(
          context,
          'Delete permanently?',
          '${picks.length} items will be removed permanently.',
          action: 'Delete',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await runFileOperation(
        context,
        action == 'restore' ? 'Restoring files…' : 'Deleting files…',
        () async {
          for (final e in picks) {
            await Native.call(action == 'restore' ? 'restore' : 'deleteTrash', {
              'id': e['id'],
            });
          }
        },
      );
      selected.clear();
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
      await load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picks = rows.where((e) => selected.contains(e['id'])).toList();
    return ExplorerPane(
      busy: busy,
      settings: widget.settings,
      windowId: widget.windowId,
      title: Text(
        selected.isEmpty ? 'Recycle Bin' : '${selected.length}/${rows.length}',
      ),
      onActivate: () => load(background: true),
      selecting: selected.isNotEmpty,
      onSelectAll: () =>
          setState(() => selected.addAll(rows.map((e) => e['id'] as String))),
      onClearSelection: () => setState(() => selected.clear()),
      onBack: selected.isNotEmpty
          ? () => setState(() => selected.clear())
          : null,
      actions: [
        ExplorerAction(
          icon: Icons.restore,
          label: 'Restore',
          enabled: !busy && picks.isNotEmpty,
          onTap: () => operate('restore', picks),
        ),
        ExplorerAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          enabled: !busy && picks.isNotEmpty,
          onTap: () => operate('delete', picks),
        ),
        ExplorerAction(
          icon: Icons.delete_sweep_outlined,
          label: 'Empty',
          enabled: !busy && rows.isNotEmpty,
          onTap: () => operate('delete', rows),
        ),
        ExplorerAction(icon: Icons.refresh, label: 'Refresh', onTap: load),
        ExplorerAction(
          icon: Icons.filter_none,
          label: 'Windows',
          onTap: () => showExplorerWindows(context),
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? EmptyState(
                    title: 'Cannot read Recycle Bin',
                    message: error!,
                    action: FilledButton(
                      onPressed: load,
                      child: const Text('Retry'),
                    ),
                  )
                : rows.isEmpty
                ? const EmptyState(
                    icon: Icons.delete_outline,
                    title: 'Recycle Bin is empty',
                    message: 'Deleted files will appear here.',
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: ExplorerBottomBar.contentBottomPadding(context),
                      ),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final e = rows[i];
                        return ListTile(
                          selected: selected.contains(e['id']),
                          leading: selected.contains(e['id'])
                              ? const Icon(
                                  Icons.check_circle,
                                  color: primaryBlue,
                                )
                              : FileGlyph(e),
                          title: Text(e['name']),
                          subtitle: Text(
                            '${e['original']}\nDeleted ${dateLabel(e['deleted'])}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          isThreeLine: true,
                          onTap: () => toggle(e),
                          onLongPress: () => toggle(e),
                          trailing: IconButton(
                            tooltip: 'Restore',
                            icon: const Icon(Icons.restore, color: primaryBlue),
                            onPressed: () => operate('restore', [e]),
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
