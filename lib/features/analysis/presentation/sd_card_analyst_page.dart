import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/analysis/presentation/storage_analysis_page.dart';
import 'package:yr_file_explorer/features/storage/presentation/dialogs/storage_locations_dialog.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/widgets/breadcrumbs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class SdCardAnalyst extends StatefulWidget {
  final AppSettings settings;
  final int? windowId;
  final String path;
  const SdCardAnalyst({
    super.key,
    required this.settings,
    required this.path,
    this.windowId,
  });
  @override
  State<SdCardAnalyst> createState() => _SdCardAnalystState();
}

class _SdCardAnalystState extends State<SdCardAnalyst> {
  late String path;
  String id = '', sort = 'Size';
  bool descending = true, scanning = true;
  Json? result, progress, storage;
  String? error;
  StreamSubscription<Json>? subscription;
  @override
  void initState() {
    super.initState();
    path = widget.path;
    subscription = Native.events.listen((e) {
      if (mounted && e['id'] == id) setState(() => progress = e);
    }, onError: (_) {});
    scan();
  }

  @override
  void dispose() {
    subscription?.cancel();
    Native.call('cancelAnalysis', {'id': id});
    super.dispose();
  }

  Future<void> scan() async {
    await Native.call('cancelAnalysis', {'id': id});
    if (!mounted) return;
    final job = 'sd-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      id = job;
      scanning = true;
      error = null;
      progress = null;
    });
    try {
      final values = await Future.wait([
        Native.call<Map>('analyze', {
          'path': path,
          'id': job,
          'duplicates': false,
        }),
        Native.call<Map>('storageStats', {'path': path}),
      ]);
      if (mounted && id == job) {
        setState(() {
          result = Map<String, dynamic>.from(values[0]!);
          storage = Map<String, dynamic>.from(values[1]!);
          scanning = false;
        });
      }
    } catch (e) {
      if (mounted && id == job) {
        setState(() {
          error = e.toString();
          scanning = false;
        });
      }
    }
  }

  void go(String value) {
    final session = ExplorerWorkspaceSession.instance;
    value = session.storagePath(value);
    if (!session.containsStoragePath(value)) return;
    if (value == path) return;
    setState(() => path = value);
    if (widget.windowId != null) {
      ExplorerWorkspaceSession.instance.updatePath(widget.windowId!, path);
    }
    scan();
  }

  List<Json> get rows {
    final entries = jsonRows(result?['children']);
    entries.sort((a, b) {
      final order = switch (sort) {
        'Name' => a['name'].toString().toLowerCase().compareTo(
          b['name'].toString().toLowerCase(),
        ),
        'Files' => ((a['files'] ?? 0) as num).compareTo(
          (b['files'] ?? 0) as num,
        ),
        'Folders' => ((a['folders'] ?? 0) as num).compareTo(
          (b['folders'] ?? 0) as num,
        ),
        _ => ((a['size'] ?? 0) as num).compareTo((b['size'] ?? 0) as num),
      };
      return descending ? -order : order;
    });
    return entries;
  }

  void sortMenu() => showDialog<void>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const Center(child: Text('Sort')),
      children: [
        for (final name in ['Name', 'Size', 'Files', 'Folders'])
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                if (sort == name) {
                  descending = !descending;
                } else {
                  sort = name;
                  descending = name != 'Name';
                }
              });
              Navigator.pop(dialog);
            },
            child: Row(
              children: [
                Expanded(child: Text(name)),
                if (sort == name)
                  Icon(
                    descending ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 18,
                    color: primaryBlue,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
  void details([String? target]) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AnalysisPage(
        path: target ?? path,
        onBrowse: (value) => ExplorerWorkspaceSession.instance.open(value),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final entries = rows, total = (storage?['total'] as num? ?? 0).toDouble();
    final largest = entries.fold<double>(
      0,
      (value, e) => (e['size'] as num).toDouble() > value
          ? (e['size'] as num).toDouble()
          : value,
    );
    Widget stat(String label, num value, Color color) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          '$label: ${sizeLabel(value)}',
          style: TextStyle(fontSize: 10, color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    return ExplorerPane(
      settings: widget.settings,
      windowId: widget.windowId,
      onBack: () {
        if (path != widget.path &&
            ExplorerWorkspaceSession.instance.containsStoragePath(
              parentPath(path),
            )) {
          go(parentPath(path));
        } else {
          ExplorerWorkspaceSession.instance.activate(null);
        }
      },
      onTitle: () => showStorageLocations(context, onSelect: go),
      title: ExplorerBreadcrumbs(
        entries: ExplorerWorkspaceSession.instance.breadcrumbsFor(path),
        onNavigate: go,
        onCurrent: () => showStorageLocations(context, onSelect: go),
      ),
      actions: [
        ExplorerAction(
          icon: Icons.bar_chart,
          label: 'Directory Analyze',
          onTap: () => details(),
        ),
        ExplorerAction(
          icon: scanning ? Icons.close : Icons.refresh,
          label: scanning ? 'Cancel' : 'Refresh',
          onTap: scanning
              ? () => Native.call('cancelAnalysis', {'id': id})
              : scan,
        ),
        ExplorerAction(
          icon: Icons.sort_by_alpha,
          label: 'Sort',
          onTap: sortMenu,
        ),
        ExplorerAction(
          icon: Icons.filter_none,
          label: 'Windows',
          onTap: () => showExplorerWindows(context),
        ),
      ],
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(63, 8, 17, 8),
            child: const Row(
              children: [
                Expanded(child: Text('Size', style: TextStyle(fontSize: 11))),
                Expanded(
                  child: Text(
                    'File/SD',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                Expanded(
                  child: Text(
                    'File/Folder',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: scanning
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(strokeWidth: 3),
                        const SizedBox(height: 14),
                        const Text('Analyzing…'),
                        const SizedBox(height: 8),
                        Text(
                          '${sizeLabel(progress?['bytes'] ?? 0)} · ${progress?['files'] ?? 0} files',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            progress?['current'] ?? path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  )
                : error != null
                ? EmptyState(
                    title: 'Analysis unavailable',
                    message: error!,
                    action: TextButton(
                      onPressed: scan,
                      child: const Text('Refresh'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i],
                          bytes = (e['size'] as num).toDouble();
                      return InkWell(
                        onTap: e['directory'] == true
                            ? () => go(e['path'])
                            : () => ExplorerWorkspaceSession.instance.open(
                                parentPath(e['path']),
                              ),
                        onLongPress: () =>
                            details(e['directory'] == true ? e['path'] : path),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 46,
                                child: FileGlyph(e, size: 36),
                              ),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    9,
                                    9,
                                    9,
                                    6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surface,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e['name'],
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              sizeLabel(bytes),
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              '${total == 0 ? '—' : (bytes / total * 100).toStringAsFixed(2)}%',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              '${e['files'] ?? 0} / ${(e['folders'] as num? ?? 0) + (e['directory'] == true ? 1 : 0)}',
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: largest == 0
                                              ? 0
                                              : (bytes / largest).clamp(0, 1),
                                          minHeight: 3,
                                          backgroundColor: primaryBlue
                                              .withValues(alpha: .07),
                                          color: primaryBlue.withValues(
                                            alpha: .45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if ((result?['skipped'] as num? ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                '${result!['skipped']} inaccessible paths skipped',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          Row(
            children: [
              stat('Total', storage?['total'] ?? 0, primaryBlue),
              stat('Used', storage?['used'] ?? 0, const Color(0xffdb8060)),
              stat('Avail', storage?['free'] ?? 0, const Color(0xff5b9b76)),
            ],
          ),
        ],
      ),
    );
  }
}
