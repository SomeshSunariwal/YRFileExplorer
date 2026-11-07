import 'package:yr_file_explorer/shared/widgets/explorer_notice.dart';

import 'dart:async';

import 'package:yr_file_explorer/features/analysis/domain/analysis_snapshot.dart';

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
  const AnalysisPage({
    super.key,
    required this.path,
    this.windowId,
    this.settings,
  });
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late String path;
  final pathHistory = <String>[];
  AnalysisSnapshot? snapshot;
  Json? get result => snapshot?.data;
  final progressDialog = AnalysisProgressDialog();
  String? error;
  bool scanning = true;
  String id = '';
  StreamSubscription<Json>? subscription;

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

  Future<void> scan({String? target, bool goingBack = false}) async {
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
        'duplicates': false,
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
          snapshot = AnalysisSnapshot(Map<String, dynamic>.from(r!));
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
        ExplorerPageRoute<void>(builder: (_) => AnalysisPage(path: next)),
      );
    }
  }

  void back() {
    if (pathHistory.isNotEmpty) {
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
      showExplorerNotice(
        context,
        'Analysis report copied to clipboard',
        icon: Icons.copy_outlined,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.windowId != null
      ? ExplorerPane(
          extendBody: true,
          settings: widget.settings!,
          windowId: widget.windowId,
          interceptBack: pathHistory.isNotEmpty,
          onBack: back,
          title: ExplorerBreadcrumbs(
            entries: [
              for (final crumb
                  in ExplorerWorkspaceSession.instance.breadcrumbsFor(path))
                (
                  crumb.$2 ==
                          ExplorerWorkspaceSession.instance.volumeFor(
                            path,
                          )?['path']
                      ? 'Folder Analysis'
                      : crumb.$1,
                  crumb.$2,
                ),
            ],
            onNavigate: drill,
            onCurrent: () => showStorageLocations(context, onSelect: drill),
          ),
          actions: [
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
              child: const Text('Folder Analysis'),
            ),
            actions: [
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
                    for (final kind in AnalysisKind.values)
                      if (kind != AnalysisKind.duplicates ||
                          r['provider'] != true)
                        toolTile(
                          kind,
                          kind == AnalysisKind.duplicates &&
                                  r['duplicatesScanned'] != true
                              ? null
                              : snapshot!.rows(kind),
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

  Widget toolTile(AnalysisKind kind, List<Json>? items) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        ExplorerWorkspaceSession.instance.open(
          path,
          page: 'analysis_results',
          category: kind.id,
          title: kind.title,
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
              child: Icon(
                switch (kind) {
                  AnalysisKind.large => Icons.insert_drive_file_outlined,
                  AnalysisKind.recent => Icons.history,
                  AnalysisKind.empty => Icons.folder_off_outlined,
                  AnalysisKind.duplicates => Icons.copy_all_outlined,
                },
                color: primaryBlue,
                size: 23,
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 30,
              child: Text(
                kind.title,
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
