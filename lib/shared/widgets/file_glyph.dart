import 'dart:io';

import 'package:yr_file_explorer/core/platform/native_bridge.dart';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

class FileGlyph extends StatelessWidget {
  final Json entry;
  final double size;
  const FileGlyph(this.entry, {super.key, this.size = 38});
  @override
  Widget build(BuildContext context) {
    final dir = entry['directory'] == true;
    final category = entry['category'] as String? ?? 'Other';
    final path = entry['path'] as String? ?? '';
    if (!dir &&
        path.startsWith('/') &&
        (path.toLowerCase().endsWith('.apk') ||
            (entry['name']?.toString().toLowerCase().endsWith('.apk') ??
                false))) {
      return _ApkFileIcon(key: ValueKey(path), entry: entry, size: size);
    }
    if (!dir &&
        (path.toLowerCase().endsWith('.pdf') ||
            (entry['name']?.toString().toLowerCase().endsWith('.pdf') ??
                false))) {
      return Icon(
        Icons.picture_as_pdf_rounded,
        size: size,
        color: const Color(0xffe44747),
      );
    }
    if (!dir &&
        category == 'Images' &&
        path.startsWith('/') &&
        !path.endsWith('.svg')) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image(
            image: ResizeImage(
              FileImage(File(path)),
              width: 160,
              height: 160,
              policy: ResizeImagePolicy.fit,
            ),
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) => Icon(
              Icons.image_outlined,
              size: size,
              color: categoryColors[category],
            ),
          ),
        ),
      );
    }
    if (dir) {
      return ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff6fd8ef), Color(0xff13a7d2)],
        ).createShader(bounds),
        child: Icon(Icons.folder_rounded, color: Colors.white, size: size),
      );
    }
    return Icon(
      categoryIcons[category] ?? Icons.insert_drive_file_outlined,
      size: size,
      color: categoryColors[category] ?? primaryBlue,
    );
  }
}

/// Lazy package artwork shared by file grids, lists, search and drag previews.
class _ApkFileIcon extends StatefulWidget {
  final Json entry;
  final double size;
  const _ApkFileIcon({super.key, required this.entry, required this.size});
  @override
  State<_ApkFileIcon> createState() => _ApkFileIconState();
}

class _ApkFileIconState extends State<_ApkFileIcon> {
  static final _cache = <String, Future<String?>>{};
  late Future<String?> icon;
  String get cacheKey =>
      '${widget.entry['path']}|${widget.entry['modified']}|${widget.entry['size']}';

  Future<String?> loadIcon() {
    final key = cacheKey;
    final cached = _cache.remove(key);
    final future =
        cached ??
        Native.call<String>('apkIcon', {
          'path': widget.entry['path'],
        }).catchError((Object _) => null);
    _cache[key] = future;
    while (_cache.length > 128) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  @override
  void initState() {
    super.initState();
    icon = loadIcon();
  }

  @override
  void didUpdateWidget(covariant _ApkFileIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry['path'] != widget.entry['path'] ||
        oldWidget.entry['modified'] != widget.entry['modified'] ||
        oldWidget.entry['size'] != widget.entry['size']) {
      icon = loadIcon();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() =>
        Icon(Icons.android, size: widget.size, color: primaryBlue);
    return SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<String?>(
        future: icon,
        builder: (context, snapshot) => snapshot.data == null
            ? fallback()
            : Image.file(
                File(snapshot.data!),
                fit: BoxFit.contain,
                cacheWidth: 192,
                cacheHeight: 192,
                errorBuilder: (_, error, stack) => fallback(),
              ),
      ),
    );
  }
}
