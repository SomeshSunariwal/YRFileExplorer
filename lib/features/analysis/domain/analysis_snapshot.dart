import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';

enum AnalysisKind {
  large('large', 'Large files'),
  recent('recent', 'Recently modified'),
  empty('empty', 'Empty folders'),
  duplicates('duplicates', 'Duplicate files');

  final String id, title;
  const AnalysisKind(this.id, this.title);
  static AnalysisKind fromId(String id) =>
      values.firstWhere((kind) => kind.id == id, orElse: () => large);
}

/// A single completed scan. Derived lists are materialized only when requested.
class AnalysisSnapshot {
  final Json data;
  final _rows = <AnalysisKind, List<Json>>{};
  AnalysisSnapshot(this.data);

  List<Json> rows(AnalysisKind kind) => _rows.putIfAbsent(
    kind,
    () => switch (kind) {
      AnalysisKind.large =>
        jsonRows(data['largest'])
            .where((entry) => (entry['size'] as num? ?? 0) >= 10 * 1024 * 1024)
            .toList(),
      AnalysisKind.recent => jsonRows(data['recent']),
      AnalysisKind.empty => jsonRows(data['empty']),
      AnalysisKind.duplicates => [
        for (final group in jsonRows(data['duplicates']))
          for (final path in group['paths'] as List? ?? const [])
            {
              'name': baseName(path.toString()),
              'path': path.toString(),
              'size': group['size'],
              'directory': false,
              'duplicateHash': group['hash'],
            },
      ],
    },
  );
}

class DuplicateFileGroup {
  final String id;
  final List<Json> files;
  const DuplicateFileGroup(this.id, this.files);
  String get name => files.first['name'].toString();
  num get size => files.first['size'] as num? ?? 0;

  static List<DuplicateFileGroup> fromRows(List<Json> rows) {
    final groups = <String, List<Json>>{};
    for (final row in rows) {
      final hash = row['duplicateHash'];
      if (hash is! String || hash.isEmpty) continue;
      groups.putIfAbsent('$hash:${row['size']}', () => []).add(row);
    }
    return [
      for (final entry in groups.entries)
        if (entry.value.length > 1) DuplicateFileGroup(entry.key, entry.value),
    ];
  }
}
