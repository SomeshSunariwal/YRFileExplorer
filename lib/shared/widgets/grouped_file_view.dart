import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';

/// Adds lazy group headings while preserving the original tiles, selection,
/// scroll controller, padding and grid geometry. Pass a new entries list when
/// a grouping field changes. None preserves the flat view.
class GroupedFileView extends StatefulWidget {
  final List<Json> entries;
  final String groupBy;
  final bool descending;
  final BoxScrollView child;
  const GroupedFileView({
    super.key,
    required this.entries,
    required this.groupBy,
    required this.descending,
    required this.child,
  });

  @override
  State<GroupedFileView> createState() => _GroupedFileViewState();
}

class _GroupedFileViewState extends State<GroupedFileView> {
  static final _number = RegExp(r'^[0-9]$');
  static final _symbol = RegExp(r'^[^\w\u0080-\uffff]$');
  final collapsed = <(bool, String)>{};
  List<_EntryGroup>? _groups;
  List<Json> get entries => widget.entries;
  String get groupBy => widget.groupBy;
  bool get descending => widget.descending;
  BoxScrollView get child => widget.child;

  @override
  void didUpdateWidget(covariant GroupedFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupBy != groupBy) collapsed.clear();
    if (!identical(oldWidget.entries, entries) ||
        oldWidget.groupBy != groupBy ||
        oldWidget.descending != descending) {
      _groups = null;
    }
  }

  List<_EntryGroup> _groupEntries() {
    final groups = <(bool, String), _EntryGroup>{};
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final folder = entry['directory'] == true;
      final bucket = _bucket(entry);
      final group = groups.putIfAbsent((
        folder,
        bucket.$1,
      ), () => _EntryGroup(bucket.$1, bucket.$2, folder));
      group.indices.add(i);
    }
    return groups.values.toList()..sort((a, b) {
      if (a.folder != b.folder) return a.folder ? -1 : 1;
      final order = a.order.compareTo(b.order);
      return descending ? -order : order;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (groupBy == 'None' || entries.isEmpty) return child;
    final ordered = _groups ??= _groupEntries();
    var visibleCount = 0;
    for (final group in ordered) {
      group.offset = visibleCount;
      if (!collapsed.contains(group.key)) {
        visibleCount += group.indices.length;
      }
    }
    final grid = child is GridView ? child as GridView : null;
    final source =
        (grid?.childrenDelegate ?? (child as ListView).childrenDelegate)
            as SliverChildBuilderDelegate;
    return CustomScrollView(
      key: child.key,
      controller: child.controller,
      primary: child.primary,
      physics: child.physics,
      shrinkWrap: child.shrinkWrap,
      scrollCacheExtent: child.scrollCacheExtent,
      keyboardDismissBehavior: child.keyboardDismissBehavior,
      clipBehavior: child.clipBehavior,
      semanticChildCount: visibleCount,
      slivers: [
        SliverPadding(
          padding: child.padding ?? EdgeInsets.zero,
          sliver: SliverMainAxisGroup(
            slivers: [
              for (final group in ordered) ...[
                SliverToBoxAdapter(
                  key: ValueKey(group.key),
                  child: Semantics(
                    header: true,
                    expanded: !collapsed.contains(group.key),
                    child: InkWell(
                      onTap: () => setState(() {
                        final key = group.key;
                        if (!collapsed.add(key)) collapsed.remove(key);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              collapsed.contains(group.key)
                                  ? Icons.chevron_right
                                  : Icons.expand_more,
                              size: 18,
                              color: primaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                group.folder && groupBy != 'Type'
                                    ? 'Folders · ${group.label}'
                                    : group.label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: primaryBlue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Divider(
                                height: 1,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${group.indices.length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!collapsed.contains(group.key))
                  _groupSliver(group, source, grid),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupSliver(
    _EntryGroup group,
    SliverChildBuilderDelegate source,
    GridView? grid,
  ) {
    final delegate = SliverChildBuilderDelegate(
      (context, index) => source.builder(context, group.indices[index]),
      childCount: group.indices.length,
      semanticIndexOffset: group.offset,
    );
    return grid == null
        ? SliverList(delegate: delegate)
        : SliverGrid(gridDelegate: grid.gridDelegate, delegate: delegate);
  }

  (String, String) _bucket(Json entry) {
    final name = displayFileName(entry['name']?.toString() ?? '').trim();
    switch (groupBy) {
      case 'Name':
        final initial = name.isEmpty
            ? '#'
            : String.fromCharCode(name.runes.first).toUpperCase();
        final label = _number.hasMatch(initial)
            ? '0–9'
            : _symbol.hasMatch(initial)
            ? '#'
            : initial;
        return (label, label);
      case 'Size':
        final size = (entry['size'] as num? ?? 0).clamp(0, double.infinity);
        if (size == 0) return ('Empty (0 B)', '0');
        if (size < 1024 * 1024) return ('Under 1 MB', '1');
        if (size < 100 * 1024 * 1024) return ('1–100 MB', '2');
        if (size < 1024 * 1024 * 1024) return ('100 MB–1 GB', '3');
        return ('1 GB and above', '4');
      case 'Type':
        if (entry['directory'] == true) return ('Folders', '');
        if (entry.containsKey('package')) {
          final type = entry['system'] == true ? 'System apps' : 'User apps';
          return (type, type);
        }
        final dot = name.lastIndexOf('.');
        final type = dot > 0 && dot < name.length - 1
            ? name.substring(dot + 1).toUpperCase()
            : 'Other files';
        return (type, type);
      default:
        return ('Other', '');
    }
  }
}

class _EntryGroup {
  final String label, order;
  final bool folder;
  final indices = <int>[];
  int offset = 0;
  _EntryGroup(this.label, this.order, this.folder);
  (bool, String) get key => (folder, label);
}
