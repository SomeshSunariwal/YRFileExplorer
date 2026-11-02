import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:yr_file_explorer/shared/widgets/operation_progress_content.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/models/json.dart';

/// Keeps the current page in place while a non-cancellable native operation runs.
Future<T> runFileOperation<T>(
  BuildContext context,
  String message,
  Future<T> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final id = 'operation-${DateTime.now().microsecondsSinceEpoch}';
  final progress = ValueNotifier<Json>({});
  void report(Json update) => progress.value = {...progress.value, ...update};
  final events = Native.events.listen((event) {
    if (event['type'] == 'fileOperation' && event['id'] == id) report(event);
  }, onError: (_) {});
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: ExplorerDialog(
        title: const Text('File operation'),
        canClose: false,
        content: ValueListenableBuilder<Json>(
          valueListenable: progress,
          builder: (context, event, _) {
            final total = event['total'] as num?;
            final completed = (event['completed'] as num?) ?? 0;
            return OperationProgressContent(
              filename: event['current']?.toString() ?? message,
              value: total != null && total > 0 ? completed / total : null,
              summary: total == null
                  ? (event['counting'] == true
                        ? 'Counting files…'
                        : 'Processing files…')
                  : '$completed / $total files',
              summaryAlignment: TextAlign.right,
            );
          },
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await Native.withFileOperation(report, id, action);
  } finally {
    await events.cancel();
    if (route.navigator != null) route.navigator!.removeRoute(route);
    // The outgoing route may still paint its last frame.
    Future<void>.delayed(const Duration(milliseconds: 300), progress.dispose);
  }
}
