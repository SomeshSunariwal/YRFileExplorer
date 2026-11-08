import 'package:yr_file_explorer/core/utils/file_sort.dart';
import 'package:yr_file_explorer/shared/dialogs/operation_progress_dialog.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets/analysis_progress_dialog.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/storage/presentation/dialogs/storage_locations_dialog.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/drag_selection_region.dart';
import 'package:yr_file_explorer/features/analysis/presentation/widgets/analysis_usage_row.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/files/presentation/open_explorer_file.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';

class SdCardAnalyst extends StatefulWidget {
  final AppSettings settings;
  final FileClipboard clipboard;
  final int? windowId;
  final String path;
  const SdCardAnalyst({
    super.key,
    required this.settings,
    required this.clipboard,
    required this.path,
    this.windowId,
  });
  @override
  State<SdCardAnalyst> createState() => _SdCardAnalystState();
}

class _SdCardAnalystState extends State<SdCardAnalyst> {
  late String path;
  String id = '', sort = 'Size';
  final selected = <String>{};
  final selectionKeys = <String, GlobalKey>{};
  final listScroll = ScrollController();
  bool descending = true, scanning = true;
  Json? result, storage;
  final progressDialog = AnalysisProgressDialog();
  Json? sortedResult;
  List<Json>? sortedRows;
  String? cachedSort;
  bool? cachedDescending;
  String? error;
  StreamSubscription<Json>? subscription;
  @override
  void initState() {
    super.initState();
    path = widget.path;
    subscription = Native.events.listen((e) {
      if (mounted && e['id'] == id) progressDialog.update(e);
    }, onError: (_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) scan();
    });
  }

  @override
  void dispose() {
    listScroll.dispose();
    progressDialog.dispose();
    subscription?.cancel();
    Native.call('cancelAnalysis', {'id': id});
    super.dispose();
  }

  Future<void> scan({String? target}) async {
    if (scanning && id.isNotEmpty) return;
    final next = target ?? path;
    final job = 'sd-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      id = job;
      selected.clear();
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
      final values = await Future.wait([
        Native.call<Map>('analyze', {
          'path': next,
          'id': job,
          'duplicates': false,
        }),
        Native.call<Map>('storageStats', {'path': next}),
      ]);
      if (mounted && id == job) {
        setState(() {
          path = next;
          result = Map<String, dynamic>.from(values[0]!);
          storage = Map<String, dynamic>.from(values[1]!);
        });
        if (widget.windowId != null) {
          ExplorerWorkspaceSession.instance.updatePath(widget.windowId!, path);
        }
      }
    } catch (e) {
      if (mounted && id == job) {
        final cancelled = e is PlatformException && e.code == 'CANCELLED';
        if (result == null) {
          setState(
            () => error = cancelled
                ? 'Analysis cancelled. Tap Refresh to try again.'
                : e.toString(),
          );
        } else if (!cancelled) {
          showError(context, e);
        }
      }
    } finally {
      if (id == job) {
        progressDialog.close();
        if (mounted) setState(() => scanning = false);
      }
    }
  }

  void go(String value) {
    final session = ExplorerWorkspaceSession.instance;
    value = session.storagePath(value);
    if (!session.containsStoragePath(value) || value == path || scanning) {
      return;
    }
    scan(target: value);
  }

  List<Json> get rows {
    if (sortedRows != null &&
        identical(sortedResult, result) &&
        cachedSort == sort &&
        cachedDescending == descending) {
      return sortedRows!;
    }
    final entries = sortedFileEntries(
      jsonRows(result?['children']),
      sort: sort,
      descending: descending,
    );
    sortedResult = result;
    final paths = entries.map((e) => e['path'] as String).toSet();
    selectionKeys.removeWhere((path, _) => !paths.contains(path));
    cachedSort = sort;
    cachedDescending = descending;
    return sortedRows = entries;
  }

  void sortMenu() => showDialog<void>(
    context: context,
    builder: (dialog) => ExplorerChoiceDialog(
      maxWidth: 280,
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
                Icon(
                  switch (name) {
                    'Name' => Icons.sort_by_alpha,
                    'Size' => Icons.data_usage,
                    'Files' => Icons.insert_drive_file_outlined,
                    _ => Icons.folder_outlined,
                  },
                  size: 20,
                  color: primaryBlue,
                ),
                const SizedBox(width: 12),
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
  void copySelection(bool cut) {
    widget.clipboard.put(selected.toList(), cut);
    setState(() => selected.clear());
  }

  Future<void> deleteSelection() async {
    final recycle = widget.settings.recycle;
    if (!await confirm(
      context,
      recycle ? 'Move to Recycle Bin?' : 'Permanently delete?',
      '${selected.length} selected items ${recycle ? 'will be moved to the bin.' : 'will be permanently deleted.'}',
      action: recycle ? 'Move' : 'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await runFileOperation(
        context,
        widget.settings.recycle
            ? 'Moving files to Recycle Bin…'
            : 'Deleting files…',
        () => Native.call('delete', {
          'paths': selected.toList(),
          'permanent': !recycle,
        }),
      );
      selected.clear();
      await scan();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void details([String? target]) => ExplorerWorkspaceSession.instance.open(
    target ?? path,
    page: 'storage_analysis',
    title: 'Folder Analysis',
  );
  @override
  Widget build(BuildContext context) {
    final entries = rows, total = (storage?['total'] as num? ?? 0).toDouble();
    final session = ExplorerWorkspaceSession.instance;
    final atStorageRoot =
        session.storagePath(path) ==
        session.storagePath(session.volumeFor(path)?['path'] ?? session.root);
    final headerTitle = atStorageRoot ? 'Storage Analyzer' : baseName(path);
    final analyzedTotal = (result?['bytes'] as num? ?? 0).toDouble();
    final free = (storage?['free'] as num? ?? 0).toDouble().clamp(
      0.0,
      total > 0 ? total : 0.0,
    );
    final used = (total - free).clamp(0.0, total > 0 ? total : 0.0);
    final usedFraction = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const usedColor = Color(0xffd32f2f);
    const freeColor = Color(0xff16843d);
    final capacityHeight =
        22 + (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0.0, 20.0);
    // Remove scroll clearance and the navigation's transparent top inset so
    // the capsule meets its visible surface, with a narrower secondary width.
    final capacityBottom = ExplorerBottomBar.contentBottomPadding(context) - 20;
    return ExplorerPane(
      extendBody: true,
      settings: widget.settings,
      windowId: widget.windowId,
      selecting: selected.isNotEmpty,
      onSelectAll: () => setState(
        () => selected.addAll(entries.map((e) => e['path'] as String)),
      ),
      onClearSelection: () => setState(() => selected.clear()),
      onBack: () {
        if (selected.isNotEmpty) {
          setState(() => selected.clear());
          return;
        }
        if (path !=
                ExplorerWorkspaceSession.instance.volumeFor(path)?['path'] &&
            ExplorerWorkspaceSession.instance.containsStoragePath(
              parentPath(path),
            )) {
          go(parentPath(path));
        } else {
          ExplorerWorkspaceSession.instance.activate(null);
        }
      },
      onTitle: () => showStorageLocations(context, onSelect: go),
      title: selected.isNotEmpty
          ? Text('${selected.length}/${entries.length}')
          : Text(headerTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: selected.isNotEmpty
          ? [
              ExplorerAction(
                icon: Icons.copy_outlined,
                label: 'Copy',
                onTap: () => copySelection(false),
              ),
              ExplorerAction(
                icon: Icons.content_cut,
                label: 'Cut',
                onTap: () => copySelection(true),
              ),
              ExplorerAction(
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: deleteSelection,
              ),
              ExplorerAction(
                icon: Icons.select_all,
                label: 'Select all',
                onTap: () => setState(
                  () =>
                      selected.addAll(entries.map((e) => e['path'] as String)),
                ),
              ),
              ExplorerAction(
                icon: Icons.filter_none,
                label: 'Windows',
                onTap: () => showExplorerWindows(context),
              ),
            ]
          : [
              ExplorerAction(
                icon: Icons.bar_chart,
                label: 'Analyze',
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.fromLTRB(68, 4, 24, 4),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text('Size', style: TextStyle(fontSize: 11)),
                    ),
                    Expanded(
                      child: Text(
                        'Share',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Files / Folders',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: error != null
                    ? EmptyState(
                        title: 'Analysis unavailable',
                        message: error!,
                        action: TextButton(
                          onPressed: scan,
                          child: const Text('Refresh'),
                        ),
                      )
                    : DragSelectionRegion(
                        continueFromLongPress: true,
                        enabled: selected.isNotEmpty,
                        itemKeys: selectionKeys,
                        scroll: listScroll,
                        isSelected: selected.contains,
                        onSelection: (path, value) => setState(() {
                          value ? selected.add(path) : selected.remove(path);
                        }),
                        child: CustomScrollView(
                          controller: listScroll,
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                capacityBottom + capacityHeight + 16,
                              ),
                              sliver: SliverList.builder(
                                itemCount: entries.length,
                                itemBuilder: (_, i) {
                                  final e = entries[i];
                                  return Padding(
                                    key: selectionKeys.putIfAbsent(
                                      e['path'] as String,
                                      GlobalKey.new,
                                    ),
                                    padding: EdgeInsets.only(
                                      bottom: i == entries.length - 1 ? 0 : 6,
                                    ),
                                    child: AnalysisUsageRow(
                                      entry: e,
                                      total: analyzedTotal,
                                      selected: selected.contains(e['path']),
                                      selectionMode: selected.isNotEmpty,
                                      onToggle: () => setState(
                                        () => selected.contains(e['path'])
                                            ? selected.remove(e['path'])
                                            : selected.add(e['path']),
                                      ),
                                      onOpen: () async {
                                        if (e['directory'] == true) {
                                          go(e['path']);
                                          return;
                                        }
                                        try {
                                          await openExplorerFile(
                                            context,
                                            e,
                                            nearby: entries,
                                            recycle: widget.settings.recycle,
                                          );
                                        } catch (error) {
                                          if (context.mounted) {
                                            showError(context, error);
                                          }
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          Positioned(
            left: 38,
            right: 38,
            bottom: capacityBottom,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: dark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .12),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Semantics(
                label: total > 0
                    ? 'Storage: ${(usedFraction * 100).toStringAsFixed(1)}% used, ${((1 - usedFraction) * 100).toStringAsFixed(1)}% available'
                    : 'Storage capacity unavailable',
                child: Tooltip(
                  message: total > 0
                      ? '${sizeLabel(used)} used · ${sizeLabel(free)} available'
                      : 'Storage capacity unavailable',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: capacityHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: total > 0
                                ? freeColor
                                : Theme.of(context).dividerColor,
                          ),
                          if (usedFraction > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: usedFraction,
                                heightFactor: 1,
                                child: ColoredBox(color: usedColor),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                for (final entry in [
                                  ('Used', used),
                                  ('Total', total),
                                  ('Avail', free),
                                ])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: entry.$1 == 'Used'
                                            ? Alignment.centerLeft
                                            : entry.$1 == 'Avail'
                                            ? Alignment.centerRight
                                            : Alignment.center,
                                        child: Text(
                                          '${entry.$1}: ${sizeLabel(entry.$2)}',
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
