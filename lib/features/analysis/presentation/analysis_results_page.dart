import 'package:yr_file_explorer/core/utils/file_sort.dart';
import 'package:yr_file_explorer/shared/dialogs/operation_progress_dialog.dart';

import 'widgets/duplicate_file_group_card.dart';

import 'dart:async';

import 'package:yr_file_explorer/features/analysis/domain/analysis_snapshot.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';
import 'package:yr_file_explorer/features/analysis/presentation/widgets/analysis_progress_dialog.dart';

class AnalysisResultsPage extends StatefulWidget {
  final AppSettings settings;
  final FileClipboard clipboard;
  final int windowId;
  final String path, kind, title;
  final Json? payload;
  const AnalysisResultsPage({
    super.key,
    required this.settings,
    required this.clipboard,
    required this.windowId,
    required this.path,
    required this.kind,
    required this.title,
    this.payload,
  });
  @override
  State<AnalysisResultsPage> createState() => _AnalysisResultsPageState();
}

class _AnalysisResultsPageState extends State<AnalysisResultsPage> {
  List<Json> rows = [];
  List<DuplicateFileGroup> duplicateGroups = [];
  final expandedGroups = <String>{};
  bool get duplicates => widget.kind == 'duplicates';

  bool acceptsPayload(Json? payload) {
    if (payload?['rows'] is! List) return false;
    final values = jsonRows(payload!['rows']);
    // Old flattened payloads did not retain verified group identity.
    if (duplicates && values.any((e) => e['duplicateHash'] is! String)) {
      return false;
    }
    replaceRows(values);
    return true;
  }

  void replaceRows(List<Json> values) {
    rows = foldersFirst(values);
    duplicateGroups = duplicates ? DuplicateFileGroup.fromRows(values) : [];
    expandedGroups.retainAll(duplicateGroups.map((g) => g.id));
    selected.clear();
  }

  final selected = <String>{};
  final progress = AnalysisProgressDialog();
  StreamSubscription<Json>? events;
  String job = '', error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    events = Native.events.listen((event) {
      if (event['id'] == job) progress.update(event);
    }, onError: (_) {});
    if (!acceptsPayload(widget.payload)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AnalysisResultsPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.payload, widget.payload) &&
        !acceptsPayload(widget.payload)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  @override
  void dispose() {
    Native.call('cancelAnalysis', {'id': job});
    events?.cancel();
    progress.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy) return;
    final id = 'analysis-items-${DateTime.now().microsecondsSinceEpoch}';
    job = id;
    setState(() {
      busy = true;
      error = '';
    });
    if (ExplorerWorkspaceSession.instance.activeId == widget.windowId) {
      progress.show(
        context,
        title: widget.kind == 'duplicates'
            ? 'Finding duplicate files'
            : 'Analyzing folder',
        folder: widget.path,
        onCancel: () => Native.call('cancelAnalysis', {'id': id}),
      );
    }
    try {
      final result = Map<String, dynamic>.from(
        (await Native.call<Map>('analyze', {
          'path': widget.path,
          'id': id,
          'duplicates': widget.kind == 'duplicates',
        }))!,
      );
      if (!mounted || job != id) return;
      final values = AnalysisSnapshot(result)
          .rows(AnalysisKind.fromId(widget.kind));
      setState(() => replaceRows(values));
    } catch (e) {
      if (mounted && !(e is PlatformException && e.code == 'CANCELLED')) {
        setState(() => error = e.toString());
      }
    } finally {
      if (job == id) {
        progress.close();
        if (mounted) setState(() => busy = false);
      }
    }
  }

  void copy(bool move) {
    widget.clipboard.put(selected.toList(), move);
    setState(() => selected.clear());
  }

  Future<void> remove() async {
    if (busy || selected.isEmpty) return;
    final paths = selected.toList();
    if (!await confirm(
      context,
      widget.settings.recycle ? 'Move to Recycle Bin?' : 'Permanently delete?',
      '${paths.length} selected items will be ${widget.settings.recycle ? 'moved to the bin.' : 'permanently deleted.'}${duplicates ? ' Unchecked copies will be kept.' : ''}',
      action: widget.settings.recycle ? 'Move' : 'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await runFileOperation(
        context,
        widget.settings.recycle
            ? 'Moving files to Recycle Bin…'
            : 'Deleting files…',
        () => Native.call('delete', {
          'paths': paths,
          'permanent': !widget.settings.recycle,
        }),
      );
      if (!mounted) return;
      setState(() => busy = false);
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showError(context, e);
      }
    }
  }

  void back() {
    if (selected.isNotEmpty) {
      setState(() => selected.clear());
      return;
    }
    final s = ExplorerWorkspaceSession.instance;
    final previous = s.previousActiveId;
    s.activate(
      previous != widget.windowId && s.windows.any((w) => w.id == previous)
          ? previous
          : null,
    );
  }

  Widget duplicateList() => ListView.builder(
    padding: EdgeInsets.fromLTRB(
      12,
      12,
      12,
      ExplorerBottomBar.contentBottomPadding(context),
    ),
    itemCount: duplicateGroups.length,
    itemBuilder: (_, i) {
      final group = duplicateGroups[i];
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DuplicateFileGroupCard(
          key: ValueKey(group.id),
          group: group,
          expanded: expandedGroups.contains(group.id),
          selected: selected,
          enabled: !busy,
          onExpand: () => setState(
            () => expandedGroups.contains(group.id)
                ? expandedGroups.remove(group.id)
                : expandedGroups.add(group.id),
          ),
          onToggle: (path) => setState(
            () => selected.contains(path)
                ? selected.remove(path)
                : selected.add(path),
          ),
          onOpen: (file) async {
            try {
              await Native.call('open', {'path': file['path']});
            } catch (e) {
              if (mounted) showError(context, e);
            }
          },
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => ExplorerPane(
    settings: widget.settings,
    windowId: widget.windowId,
    onBack: back,
    selecting: selected.isNotEmpty,
    selectAllLabel: duplicates ? 'Select extras' : 'Select all',
    onSelectAll: () => setState(() {
      if (duplicates) {
        selected.clear();
        selected.addAll([
          for (final group in duplicateGroups)
            for (final file in group.files.skip(1)) file['path'] as String,
        ]);
      } else {
        selected.addAll(rows.map((e) => e['path'] as String));
      }
    }),
    onClearSelection: () => setState(() => selected.clear()),
    title: Text(
      selected.isEmpty ? widget.title : '${selected.length}/${rows.length}',
    ),
    actions: selected.isEmpty
        ? [
            ExplorerAction(
              icon: Icons.refresh,
              label: 'Refresh',
              onTap: refresh,
              enabled: !busy,
            ),
            ExplorerAction(
              icon: Icons.filter_none,
              label: 'Windows',
              onTap: () => showExplorerWindows(context),
            ),
          ]
        : [
            if (!duplicates)
              ExplorerAction(
                icon: Icons.copy_outlined,
                label: 'Copy',
                onTap: () => copy(false),
              ),
            if (!duplicates)
              ExplorerAction(
                icon: Icons.content_cut,
                label: 'Cut',
                onTap: () => copy(true),
              ),
            ExplorerAction(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: remove,
            ),
            ExplorerAction(
              icon: Icons.select_all,
              label: duplicates ? 'Select extras' : 'Select all',
              onTap: () => setState(() {
                if (duplicates) {
                  selected.clear();
                  selected.addAll([
                    for (final group in duplicateGroups)
                      for (final file in group.files.skip(1))
                        file['path'] as String,
                  ]);
                } else {
                  selected.addAll(rows.map((e) => e['path'] as String));
                }
              }),
            ),
            if (duplicates)
              ExplorerAction(
                icon: Icons.deselect,
                label: 'Clear',
                onTap: () => setState(() => selected.clear()),
              ),
            ExplorerAction(
              icon: Icons.filter_none,
              label: 'Windows',
              onTap: () => showExplorerWindows(context),
            ),
          ],
    body: error.isNotEmpty
        ? EmptyState(
            title: 'Analysis unavailable',
            message: error,
            action: TextButton(
              onPressed: refresh,
              child: const Text('Try again'),
            ),
          )
        : rows.isEmpty
        ? EmptyState(
            icon: Icons.search_off,
            title: busy ? 'Analyzing…' : 'No items found',
            message: widget.kind == 'large'
                ? 'Files larger than 10 MB appear here.'
                : '',
          )
        : duplicates
        ? duplicateList()
        : ListView.builder(
            padding: EdgeInsets.only(
              bottom: ExplorerBottomBar.contentBottomPadding(context),
            ),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final e = rows[i], path = e['path'] as String;
              void toggle() => setState(
                () => selected.contains(path)
                    ? selected.remove(path)
                    : selected.add(path),
              );
              return ListTile(
                selected: selected.contains(path),
                leading: FileGlyph(e, size: 34),
                title: Text(
                  e['name'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${sizeLabel(e['size'] ?? 0)} · $path',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: selected.isNotEmpty
                    ? Checkbox(
                        value: selected.contains(path),
                        onChanged: (_) => toggle(),
                      )
                    : const Icon(Icons.chevron_right, size: 20),
                onLongPress: toggle,
                onTap: () async {
                  if (selected.isNotEmpty) {
                    toggle();
                    return;
                  }
                  if (e['directory'] == true) {
                    ExplorerWorkspaceSession.instance.open(path);
                  } else {
                    try {
                      await Native.call('open', {'path': path});
                    } catch (error) {
                      if (context.mounted) showError(context, error);
                    }
                  }
                },
              );
            },
          ),
  );
}
