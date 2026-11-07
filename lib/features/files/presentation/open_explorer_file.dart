import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/editor/presentation/text_editor_page.dart';
import 'package:yr_file_explorer/features/gallery/presentation/image_viewer_page.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_notice.dart';

final _editableText = RegExp(
  r'\.(txt|md|json|xml|html|csv|log|dart|java|yaml|yml|ini|sh|css|js)$',
  caseSensitive: false,
);

bool _isGalleryImage(Json entry) =>
    entry['directory'] != true &&
    entry['category'] == 'Images' &&
    entry['path'] is String &&
    (entry['path'] as String).startsWith('/') &&
    !(entry['path'] as String).toLowerCase().endsWith('.svg');

/// Returns whether an editable viewer was shown and the caller may need to reload.
Future<bool> openExplorerFile(
  BuildContext context,
  Json entry, {
  Iterable<Json> nearby = const [],
  bool recycle = true,
  bool readOnly = false,
  Future<void> Function(String path)? openArchive,
}) async {
  final path = entry['path'] as String;
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  dismissExplorerNotice();
  if (_isGalleryImage(entry)) {
    await Navigator.of(context).push(
      ExplorerPageRoute<void>(
        builder: (_) => ImageViewer(
          path: path,
          recycle: recycle,
          canDelete: !readOnly,
          images: nearby
              .where(_isGalleryImage)
              .map((item) => item['path'] as String)
              .toList(),
        ),
      ),
    );
    return !readOnly;
  }
  if (path.startsWith('/') && _editableText.hasMatch(path)) {
    await Navigator.of(context).push(
      ExplorerPageRoute<void>(
        builder: (_) => TextEditor(path: path, readOnly: readOnly),
      ),
    );
    return !readOnly;
  }
  if (!readOnly && path.startsWith('/') && isSupportedArchive(path)) {
    if (openArchive != null) {
      await openArchive(path);
    } else {
      ExplorerWorkspaceSession.instance.open(
        path,
        page: 'archive',
        title: baseName(path),
      );
    }
    return false;
  }
  await Native.call('open', {'path': path});
  return false;
}
