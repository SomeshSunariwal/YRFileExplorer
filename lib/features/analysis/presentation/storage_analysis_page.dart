import 'dart:async';

import 'widgets/analysis_progress_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/analysis/presentation/widgets/storage_ring_painter.dart';
import 'package:yr_file_explorer/features/storage/presentation/dialogs/storage_locations_dialog.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/breadcrumbs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';

class AnalysisPage extends StatefulWidget {
  final String path;
  final int? windowId;
  final AppSettings? settings;
  final void Function(String path)? onBrowse;
  const AnalysisPage({
    super.key,
    required this.path,
    this.onBrowse,
    this.windowId,
    this.settings,
  });
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late String path;
  final pathHistory = <String>[];
  Json? result;
  final progressDialog = AnalysisProgressDialog();
  String? error;
  bool scanning = true, duplicateScan = false;
  String id = '', filter = 'All', sort = 'Size';
  StreamSubscription<Json>? subscription;
  final selected = <String>{};

  @override
  void initState() {
    super.initState();
    path = widget.path;
    subscription = Native.events.listen((e) {
      if (mounted && e['id'] == id) progressDialog.update(e);
    }, onError: (Object e) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) scan();
    });
  }

  Future<void> scan({
    bool duplicates = false,
    String? target,
    bool goingBack = false,
  }) async {
    if (scanning && id.isNotEmpty) return;
    final next = target ?? path;
    final previous = id;
    if (previous.isNotEmpty) {
      await Native.call('cancelAnalysis', {'id': previous});
    }
    if (!mounted) return;
    final job = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      id = job;
      scanning = true;
      error = null;
      duplicateScan = duplicates;
      selected.clear();
    });
    if (widget.windowId == null ||
        ExplorerWorkspaceSession.instance.activeId == widget.windowId) {
      progressDialog.show(
        context,
        title: 'Analyzing folder',
        folder: next,
        onCancel: () => Native.call('cancelAnalysis', {'id': job}),
      );
    }
    try {
      final r = await Native.call<Map>('analyze', {
        'path': next,
        'id': job,
        'duplicates': duplicates,
      });
      if (mounted && id == job) {
        setState(() {
          if (next != path) {
            if (goingBack) {
              if (pathHistory.isNotEmpty) pathHistory.removeLast();
            } else {
              final previous = pathHistory.lastIndexOf(path);
              if (previous >= 0) {
                pathHistory.removeRange(previous, pathHistory.length);
              }
              pathHistory.add(path);
            }
            path = next;
          }
          result = Map<String, dynamic>.from(r!);
          scanning = false;
        });
        if (widget.windowId != null) {
          ExplorerWorkspaceSession.instance.updatePath(widget.windowId!, path);
        }
      }
    } catch (e) {
      if (mounted && id == job) {
        setState(() {
          scanning = false;
          if (result == null) {
            error = e is PlatformException && e.code == 'CANCELLED'
                ? 'Analysis cancelled. Tap refresh to scan again.'
                : e.toString();
          }
        });
      }
    } finally {
      if (id == job) progressDialog.close();
    }
  }

  @override
  void dispose() {
    progressDialog.dispose();
    subscription?.cancel();
    Native.call('cancelAnalysis', {'id': id});
    super.dispose();
  }

  void drill(String next) {
    if (next == path) return;
    if (widget.windowId != null) {
      scan(target: next);
    } else {
      Navigator.push(
        context,
        ExplorerPageRoute<void>(
          builder: (_) => AnalysisPage(path: next, onBrowse: widget.onBrowse),
        ),
      );
    }
  }

  void back() {
    if (selected.isNotEmpty) {
      setState(() => selected.clear());
    } else if (pathHistory.isNotEmpty) {
      scan(target: pathHistory.last, goingBack: true);
    } else {
      final session = ExplorerWorkspaceSession.instance;
      final previous = session.previousActiveId;
      session.activate(
        previous != widget.windowId &&
                session.windows.any((w) => w.id == previous)
            ? previous
            : null,
      );
    }
  }

  List<Json> get children {
    final rows = jsonRows(result?['children'])
        .where(
          (e) =>
              filter == 'All' ||
              (filter == 'Folders'
                  ? e['directory'] == true
                  : e['directory'] != true),
        )
        .toList();
    rows.sort(
      (a, b) => switch (sort) {
        'Name' => a['name'].toString().toLowerCase().compareTo(
          b['name'].toString().toLowerCase(),
        ),
        'Files' => ((b['files'] ?? 0) as num).compareTo(
          (a['files'] ?? 0) as num,
        ),
        'Folders' => ((b['folders'] ?? 0) as num).compareTo(
          (a['folders'] ?? 0) as num,
        ),
        _ => ((b['size'] ?? 0) as num).compareTo((a['size'] ?? 0) as num),
      },
    );
    return rows;
  }

  Future<void> removeSelection() async {
    if (!await confirm(
      context,
      'Move to Recycle Bin?',
      '${selected.length} selected items will be moved to the Recycle Bin.',
      action: 'Move',
    )) {
      return;
    }
    try {
      await Native.call('delete', {
        'paths': selected.toList(),
        'permanent': false,
      });
      await scan();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> export() async {
    if (result == null) return;
    final text = StringBuffer(
      'YR File Explorer — Folder Analysis\n$path\n\nSize: ${sizeLabel(result!['bytes'])} (${result!['bytes']} bytes)\nFiles: ${result!['files']}\nFolders: ${result!['folders']}\nSkipped paths: ${result!['skipped']}\n\n',
    );
    for (final e in jsonRows(result!['children'])) {
      text.writeln(
        '${e['name']}\t${e['size']} bytes\t${e['files']} files\t${e['folders']} folders',
      );
    }
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analysis report copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.windowId != null
      ? ExplorerPane(
          extendBody: true,
          settings: widget.settings!,
          windowId: widget.windowId,
          selecting: selected.isNotEmpty,
          interceptBack: pathHistory.isNotEmpty,
          onBack: back,
          title: selected.isNotEmpty
              ? Text('${selected.length} selected')
              : ExplorerBreadcrumbs(
                  entries: [
                    for (final crumb
                        in ExplorerWorkspaceSession.instance.breadcrumbsFor(
                          path,
                        ))
                      (
                        crumb.$2 ==
                                ExplorerWorkspaceSession.instance.volumeFor(
                                  path,
                                )?['path']
                            ? 'Storage Analyzer'
                            : crumb.$1,
                        crumb.$2,
                      ),
                  ],
                  onNavigate: drill,
                  onCurrent: () =>
                      showStorageLocations(context, onSelect: drill),
                ),
          actions: [
            if (selected.isNotEmpty && result?['provider'] != true)
              ExplorerAction(
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: removeSelection,
              ),
            ExplorerAction(
              icon: Icons.copy_outlined,
              label: 'Copy report',
              onTap: scanning ? () {} : export,
            ),
            ExplorerAction(
              icon: scanning ? Icons.close : Icons.refresh,
              label: scanning ? 'Cancel' : 'Refresh',
              onTap: scanning
                  ? () => Native.call('cancelAnalysis', {'id': id})
                  : scan,
            ),
            ExplorerAction(
              icon: Icons.filter_none,
              label: 'Windows',
              onTap: () => showExplorerWindows(context),
            ),
          ],
          body: analysisBody(),
        )
      : Scaffold(
          appBar: AppBar(
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(explorerHeaderHeight),
              child: SizedBox(
                height: explorerHeaderHeight,
                child: ExplorerBreadcrumbs(
                  entries: ExplorerWorkspaceSession.instance.breadcrumbsFor(
                    path,
                  ),
                  onNavigate: (next) {
                    if (next != path) drill(next);
                  },
                  onCurrent: () =>
                      showStorageLocations(context, onSelect: drill),
                ),
              ),
            ),
            centerTitle: false,
            titleSpacing: 0,
            title: Transform.translate(
              offset: const Offset(-11, 0),
              child: Text(
                selected.isEmpty
                    ? 'Storage Analyzer'
                    : '${selected.length} selected',
              ),
            ),
            actions: [
              if (selected.isNotEmpty && result?['provider'] != true)
                IconButton(
                  tooltip: 'Move to Recycle Bin',
                  onPressed: removeSelection,
                  icon: const Icon(Icons.delete_outline),
                ),
              IconButton(
                tooltip: 'Copy report',
                onPressed: scanning ? null : export,
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: scanning ? 'Cancel analysis' : 'Analyze again',
                onPressed: scanning
                    ? () => Native.call('cancelAnalysis', {'id': id})
                    : scan,
                icon: Icon(scanning ? Icons.close : Icons.refresh),
              ),
            ],
          ),
          body: analysisBody(),
        );

  Widget analysisBody() => SafeArea(
    top: false,
    bottom: false,
    child: error != null
        ? EmptyState(
            icon: Icons.info_outline,
            title: 'Analysis unavailable',
            message: error!,
            action: FilledButton(
              onPressed: scan,
              child: const Text('Try again'),
            ),
          )
        : result == null
        ? const SizedBox.shrink()
        : _results(),
  );
  Widget _stat(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: primaryBlue,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
  Widget _results() {
    final r = result!, total = (r['bytes'] as num).toDouble();
    final cats = jsonRows(r['categories']);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      SizedBox(
                        width: constraints.maxWidth * .40,
                        height: 150,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 136,
                              height: 136,
                              child: CustomPaint(
                                painter: RingPainter(
                                  cats,
                                  total,
                                  Theme.of(context).dividerColor
                                      .withValues(alpha: .2),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  sizeLabel(total),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Total size',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: cats
                              .map(
                                (c) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        color: categoryColors[c['name']],
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          c['name'],
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Text(
                                        sizeLabel(c['size']),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    _stat('Files', countLabel(r['files'])),
                    _stat('Folders', countLabel(r['folders'])),
                    _stat('Size', sizeLabel(r['bytes'])),
                  ],
                ),
                if ((r['unknownSizes'] as num? ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${r['unknownSizes']} files have no size reported by this provider. Their sizes are excluded from the total.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              ExplorerBottomBar.contentBottomPadding(context),
            ),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    toolTile(
                      'Large files',
                      Icons.insert_drive_file_outlined,
                      jsonRows(r['largest'])
                          .where((e) => (e['size'] as num) >= 10 * 1024 * 1024)
                          .toList(),
                    ),
                    toolTile(
                      'Recently modified',
                      Icons.history,
                      jsonRows(r['recent']),
                    ),
                    toolTile(
                      'Empty folders',
                      Icons.folder_off_outlined,
                      jsonRows(r['empty']),
                    ),
                    if (r['provider'] != true)
                      toolTile(
                        'Duplicate files',
                        Icons.copy_all_outlined,
                        r['duplicatesScanned'] == true
                            ? duplicateRows(r)
                            : null,
                        duplicates: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Json> duplicateRows(Json data) => [
    for (final group in jsonRows(data['duplicates']))
      for (final item in group['paths'] as List)
        {
          'name': baseName(item.toString()),
          'path': item.toString(),
          'size': group['size'],
          'directory': false,
        },
  ];

  Widget toolTile(
    String title,
    IconData icon,
    List<Json>? items, {
    bool duplicates = false,
  }) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        final kind = duplicates
            ? 'duplicates'
            : title == 'Large files'
            ? 'large'
            : title == 'Empty folders'
            ? 'empty'
            : 'recent';
        ExplorerWorkspaceSession.instance.open(
          path,
          page: 'analysis_results',
          category: kind,
          title: title,
          payload: items == null ? null : {'rows': items},
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryBlue.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: primaryBlue, size: 23),
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 30,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ),
            Text(
              items == null ? '—' : '${items.length}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  );
}
