import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/core/models/json.dart';

/// Keep each group's existing order when a view has no user-selected sort.
List<Json> foldersFirst(Iterable<Json> entries) {
  final folders = <Json>[];
  final files = <Json>[];
  for (final entry in entries) {
    (entry['directory'] == true ? folders : files).add(entry);
  }
  return [...folders, ...files];
}

/// Sort a copy so view changes never mutate the underlying directory snapshot.
List<Json> sortedFileEntries(
  List<Json> entries, {
  required String sort,
  required bool descending,
}) {
  // Normalize each key once, rather than allocating lowercase strings on
  // every comparison (O(n log n) comparisons for a large directory).
  final keys = <Json, Comparable<dynamic>>{};
  for (final entry in entries) {
    keys[entry] = switch (sort) {
      'Size' => entry['size'] as num? ?? 0,
      'Files' => entry['files'] as num? ?? 0,
      'Folders' => entry['folders'] as num? ?? 0,
      'Modified' => entry['modified'] as num? ?? 0,
      'Type' => entry['category'].toString(),
      _ => displayFileName(entry['name'].toString()).toLowerCase(),
    };
  }
  final rows = List<Json>.of(entries);
  rows.sort((a, b) {
    if ((a['directory'] == true) != (b['directory'] == true)) {
      return a['directory'] == true ? -1 : 1;
    }
    final compared = keys[a]!.compareTo(keys[b]!);
    return descending ? -compared : compared;
  });
  return rows;
}
