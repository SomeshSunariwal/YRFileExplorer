import 'package:yr_file_explorer/shared/widgets/operation_progress_content.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';

/// Owns exactly one progress route; closing it never pops another app dialog.
class AnalysisProgressDialog {
  final _progress = ValueNotifier<Json>({});
  DialogRoute<void>? _route;
  bool _disposed = false;
  void update(Json event) {
    if (!_disposed) _progress.value = event;
  }

  void show(
    BuildContext context, {
    required String title,
    required String folder,
    required VoidCallback onCancel,
  }) {
    if (_disposed) return;
    close();
    _progress.value = {};
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onCancel();
        },
        child: ExplorerDialog(
          onClose: onCancel,
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          content: ValueListenableBuilder<Json>(
            valueListenable: _progress,
            builder: (context, value, _) => OperationProgressContent(
              filename: value['current']?.toString() ?? folder,
              summary:
                  '${sizeLabel(value['bytes'] ?? 0)} · ${value['files'] ?? 0} files',
            ),
          ),
          actions: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
    _route = route;
    Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
      if (identical(_route, route)) _route = null;
    });
  }

  void close() {
    final route = _route;
    _route = null;
    if (route?.navigator != null) route!.navigator!.removeRoute(route);
  }

  void dispose() {
    close();
    _disposed = true;
    _progress.dispose();
  }
}
