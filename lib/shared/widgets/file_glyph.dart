import 'dart:io';

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
