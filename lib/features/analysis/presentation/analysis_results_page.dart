import 'dart:async';

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
    if (widget.payload?['rows'] is List) {
      rows = jsonRows(widget.payload!['rows']);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AnalysisResultsPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.payload, widget.payload) &&
        widget.payload?['rows'] is List) {
      rows = jsonRows(widget.payload!['rows']);
      selected.clear();
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
      final values = switch (widget.kind) {
        'large' => jsonRows(
          result['largest'],
        ).where((e) => (e['size'] as num) >= 10 * 1024 * 1024).toList(),
        'recent' => jsonRows(result['recent']),
        'empty' => jsonRows(result['empty']),
        _ => <Json>[
          for (final group in jsonRows(result['duplicates']))
            for (final item in group['paths'] as List)
              {
                'name': baseName(item.toString()),
                'path': item.toString(),
                'size': group['size'],
                'directory': false,
              },
        ],
      };
      setState(() {
        rows = values;
        selected.clear();
      });
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
    if (!await confirm(
      context,
      widget.settings.recycle ? 'Move to Recycle Bin?' : 'Permanently delete?',
      '${selected.length} selected items will be ${widget.settings.recycle ? 'moved to the bin.' : 'permanently deleted.'}',
      action: widget.settings.recycle ? 'Move' : 'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await Native.call('delete', {
        'paths': selected.toList(),
        'permanent': !widget.settings.recycle,
      });
      await refresh();
    } catch (e) {
      if (mounted) showError(context, e);
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

  @override
  Widget build(BuildContext context) => ExplorerPane(
    settings: widget.settings,
    windowId: widget.windowId,
    onBack: back,
    selecting: selected.isNotEmpty,
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
            ExplorerAction(
              icon: Icons.copy_outlined,
              label: 'Copy',
              onTap: () => copy(false),
            ),
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
              label: 'Select all',
              onTap: () => setState(
                () => selected.addAll(rows.map((e) => e['path'] as String)),
              ),
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
