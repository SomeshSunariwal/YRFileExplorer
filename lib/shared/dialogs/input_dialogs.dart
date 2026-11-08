import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_notice.dart';

void showError(BuildContext context, Object error) {
  if (!context.mounted) return;
  final message = error is PlatformException
      ? error.message ?? error.code
      : error.toString();
  showExplorerNotice(
    context,
    message,
    icon: Icons.error_outline,
    error: true,
    duration: const Duration(seconds: 6),
  );
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String label = 'Name',
  bool secret = false,
  String? description,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => ExplorerDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(description),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: secret,
              decoration: InputDecoration(labelText: label),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  // Dialog route animations may still reference its controller for a frame.
  Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
  return result;
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Continue',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => ExplorerDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<bool?> chooseNewItemType(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (dialog) => ExplorerChoiceDialog(
    title: const Text('New'),
    children: [
      ExplorerChoiceTile(
        icon: Icons.insert_drive_file_outlined,
        label: 'File',
        onTap: () => Navigator.pop(dialog, false),
      ),
      ExplorerChoiceTile(
        icon: Icons.create_new_folder_outlined,
        label: 'Folder',
        onTap: () => Navigator.pop(dialog, true),
      ),
    ],
  ),
);
