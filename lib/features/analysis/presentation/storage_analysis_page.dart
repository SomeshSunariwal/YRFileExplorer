import 'dart:async';

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
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class AnalysisPage extends StatefulWidget {
  final String path;
  final void Function(String path)? onBrowse;
  const AnalysisPage({super.key, required this.path, this.onBrowse});
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  Json? result, progress;
  String? error;
  bool scanning = true, duplicateScan = false;
  String id = '', filter = 'All', sort = 'Size';
  StreamSubscription<Json>? subscription;
  final selected = <String>{};

  @override
  void initState() {
    super.initState();
    subscription = Native.events.listen((e) {
      if (mounted && e['id'] == id) setState(() => progress = e);
    }, onError: (Object e) {});
    scan();
  }

  Future<void> scan({bool duplicates = false}) async {
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
      progress = null;
      duplicateScan = duplicates;
      selected.clear();
    });
    try {
      final r = await Native.call<Map>('analyze', {
        'path': widget.path,
        'id': job,
        'duplicates': duplicates,
      });
      if (mounted && id == job) {
        setState(() {
          result = Map<String, dynamic>.from(r!);
          scanning = false;
        });
      }
    } on PlatformException catch (e) {
      if (mounted && id == job) {
        setState(() {
          scanning = false;
          error = e.code == 'CANCELLED'
              ? 'Analysis cancelled. Tap refresh to scan again.'
              : e.message;
        });
      }
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    Native.call('cancelAnalysis', {'id': id});
    super.dispose();
  }

  void drill(String path) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AnalysisPage(path: path, onBrowse: widget.onBrowse),
    ),
  );
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
      'YR File Explorer — Folder Analysis\n${widget.path}\n\nSize: ${sizeLabel(result!['bytes'])} (${result!['bytes']} bytes)\nFiles: ${result!['files']}\nFolders: ${result!['folders']}\nSkipped paths: ${result!['skipped']}\n\n',
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(explorerHeaderHeight),
        child: SizedBox(
          height: explorerHeaderHeight,
          child: ExplorerBreadcrumbs(
            entries: ExplorerWorkspaceSession.instance.breadcrumbsFor(
              widget.path,
            ),
            onNavigate: (path) {
              if (path != widget.path) drill(path);
            },
            onCurrent: () => showStorageLocations(context, onSelect: drill),
          ),
        ),
      ),
      title: Text(
        selected.isEmpty ? 'Storage Analyzer' : '${selected.length} selected',
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
    body: SafeArea(
      top: false,
      bottom: false,
      child: scanning
          ? _scanning()
          : error != null
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
    ),
  );
  Widget _scanning() {
    final p = progress ?? {};
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(strokeWidth: 5),
            ),
            const SizedBox(height: 30),
            Text(
              duplicateScan ? 'Analyzing files & duplicates…' : 'Analyzing…',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(widget.path, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            Row(
              children: [
                _stat('Size', sizeLabel(p['bytes'] ?? 0)),
                _stat('Files', countLabel(p['files'] ?? 0)),
                _stat('Folders', countLabel(p['folders'] ?? 0)),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              p['current'] ?? 'Reading folder…',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Native.call('cancelAnalysis', {'id': id}),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w500,
            color: primaryBlue,
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
  Widget _results() {
    final r = result!, total = (r['bytes'] as num).toDouble();
    final rows = children;
    final cats = jsonRows(r['categories']);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_open, color: primaryBlue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.path,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Browse folder',
                      onPressed: () {
                        widget.onBrowse?.call(widget.path);
                      },
                      icon: const Icon(Icons.open_in_new, size: 19),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                const Divider(height: 28),
                Row(
                  children: [
                    _stat('Files', countLabel(r['files'])),
                    _stat('Folders', countLabel(r['folders'])),
                    _stat('Size', sizeLabel(r['bytes'])),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '${countLabel(r['bytes'])} bytes',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                if ((r['skipped'] as num) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${r['skipped']} paths could not be read or were symbolic links. Totals cover accessible files only.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
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
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.bar_chart, color: primaryBlue, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Space usage',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Sort analysis',
                  initialValue: sort,
                  onSelected: (v) => setState(() => sort = v),
                  itemBuilder: (_) => ['Size', 'Name', 'Files', 'Folders']
                      .map(
                        (e) =>
                            PopupMenuItem(value: e, child: Text('Sort by $e')),
                      )
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Text(sort, style: const TextStyle(fontSize: 12)),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['All', 'Folders', 'Files']
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e),
                        selected: filter == e,
                        onSelected: (_) => setState(() => filter = e),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        if (rows.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'This folder contains no matching items.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) => _usageRow(rows[index], total, index),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'More analysis',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              _group(
                'Large files',
                Icons.insert_drive_file_outlined,
                jsonRows(r['largest'])
                    .where((e) => (e['size'] as num) >= 10 * 1024 * 1024)
                    .toList(),
                subtitle: 'Files larger than 10 MB · up to 100 largest',
              ),
              _group(
                'Recently modified',
                Icons.history,
                jsonRows(r['recent']),
                subtitle: '100 most recently modified files',
              ),
              _group(
                'Empty folders',
                Icons.folder_off_outlined,
                jsonRows(r['empty']),
                subtitle: 'Up to 1,000 empty folders · review before deleting',
              ),
              if (r['duplicatesScanned'] == true)
                ExpansionTile(
                  leading: const Icon(Icons.copy_all, color: primaryBlue),
                  title: const Text('Duplicate files'),
                  subtitle: Text(
                    '${jsonRows(r['duplicates']).length} groups · verified with SHA-256',
                  ),
                  children: jsonRows(r['duplicates'])
                      .map(
                        (g) => ExpansionTile(
                          title: Text(
                            '${(g['paths'] as List).length} copies · ${sizeLabel(g['size'])} each',
                          ),
                          subtitle: Text(
                            '${sizeLabel(g['wasted'])} extra storage',
                          ),
                          children: (g['paths'] as List)
                              .map(
                                (p) => ListTile(
                                  title: Text(baseName(p.toString())),
                                  subtitle: Text(p.toString()),
                                  onTap: () => Native.call('open', {'path': p})
                                      .catchError((Object e) {
                                        if (mounted) showError(context, e);
                                        return null;
                                      }),
                                ),
                              )
                              .toList(),
                        ),
                      )
                      .toList(),
                )
              else if (r['provider'] != true)
                ListTile(
                  leading: const Icon(Icons.copy_all, color: primaryBlue),
                  title: const Text('Duplicate files'),
                  subtitle: const Text('Compare contents with SHA-256'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => scan(duplicates: true),
                ),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Sizes use 1 KB = 1,024 bytes. Counts include all nested items, including hidden files. The selected folder itself is excluded from the folder count.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _usageRow(Json e, double total, int index) {
    final path = e['path'] as String;
    final directory = e['directory'] == true;
    final fraction = total == 0
        ? 0.0
        : ((e['size'] as num) / total).clamp(0.0, 1.0);
    final color = directory
        ? primaryBlue
        : categoryColors[e['category']] ?? primaryBlue;
    return InkWell(
      onLongPress: () => setState(() {
        selected.contains(path) ? selected.remove(path) : selected.add(path);
      }),
      onTap: () {
        if (selected.isNotEmpty) {
          setState(() {
            selected.contains(path)
                ? selected.remove(path)
                : selected.add(path);
          });
        } else if (directory) {
          drill(path);
        } else {
          Native.call('open', {'path': path}).catchError((Object ex) {
            if (mounted) showError(context, ex);
            return null;
          });
        }
      },
      child: Container(
        color: selected.contains(path)
            ? primaryBlue.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 9, 10, 9),
        child: Row(
          children: [
            FileGlyph(e, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction,
                        child: Container(color: color.withValues(alpha: .10)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e['name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                sizeLabel(e['size']),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            if (directory) ...[
                              Expanded(
                                child: Text(
                                  '${countLabel(e['folders'] ?? 0)} folders',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${countLabel(e['files'] ?? 0)} files',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ] else
                              Text(
                                '${(fraction * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            selected.contains(path)
                ? const Icon(Icons.check_circle, size: 20, color: primaryBlue)
                : Icon(
                    directory ? Icons.chevron_right : Icons.more_vert,
                    size: 19,
                    color: Colors.grey,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _group(
    String title,
    IconData icon,
    List<Json> rows, {
    required String subtitle,
  }) => ExpansionTile(
    leading: Icon(icon, color: primaryBlue),
    title: Text('$title (${rows.length})'),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
    children: rows.isEmpty
        ? [const ListTile(title: Text('No items found'))]
        : rows
              .map(
                (e) => ListTile(
                  dense: true,
                  leading: FileGlyph(e, size: 28),
                  title: Text(
                    e['name'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    e['path'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    sizeLabel(e['size']),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    if (e['directory'] == true) {
                      drill(e['path']);
                    } else {
                      Native.call('open', {'path': e['path']}).catchError((
                        Object ex,
                      ) {
                        if (mounted) showError(context, ex);
                        return null;
                      });
                    }
                  },
                ),
              )
              .toList(),
  );
}
