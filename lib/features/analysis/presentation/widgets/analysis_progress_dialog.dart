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
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          content: SizedBox(
            width: 320,
            child: ValueListenableBuilder<Json>(
              valueListenable: _progress,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(
                    minHeight: 3,
                    borderRadius: BorderRadius.all(Radius.circular(3)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${sizeLabel(value['bytes'] ?? 0)} · ${value['files'] ?? 0} files',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value['current']?.toString() ?? folder,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
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
