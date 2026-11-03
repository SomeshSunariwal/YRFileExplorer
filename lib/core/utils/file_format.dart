String sizeLabel(num bytes, {int decimals = 2}) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : decimals)} ${units[unit]}';
}

String countLabel(num count) => count.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);

/// Hidden names retain their leading dot on disk, but use opacity in listings.
String displayFileName(String name) =>
    name.startsWith('.') && name.length > 1 ? name.substring(1) : name;
String baseName(String path) =>
    path
        .replaceAll('\\', '/')
        .split('/')
        .where((e) => e.isNotEmpty)
        .lastOrNull ??
    path;
String parentPath(String path) {
  final normalized = path
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '');
  final i = normalized.lastIndexOf('/');
  return i <= 0 ? '/' : normalized.substring(0, i);
}

String dateLabel(num timestamp) {
  if (timestamp == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

final _archiveExtension = RegExp(r'\.(zip|7z)$', caseSensitive: false);

bool isSupportedArchive(String name) => _archiveExtension.hasMatch(name);
String archiveStem(String name) => name.replaceFirst(_archiveExtension, '');
