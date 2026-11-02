import 'package:yr_file_explorer/shared/widgets/explorer_dropdown_field.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';

Future<Json?> showCreateArchiveDialog(BuildContext context, String name) =>
    showDialog<Json>(
      context: context,
      builder: (_) => _CreateArchiveDialog(name: name),
    );

class _CreateArchiveDialog extends StatefulWidget {
  final String name;
  const _CreateArchiveDialog({required this.name});
  @override
  State<_CreateArchiveDialog> createState() => _CreateArchiveDialogState();
}

class _CreateArchiveDialogState extends State<_CreateArchiveDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  final password = TextEditingController();
  String format = 'zip';
  bool obscure = true;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${archiveStem(widget.name)}.zip');
  }

  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  void create() {
    if (!form.currentState!.validate()) return;
    final stem = archiveStem(name.text.trim());
    Navigator.pop(context, <String, dynamic>{
      'name': '$stem.$format',
      'format': format,
      'password': password.text,
    });
  }

  @override
  Widget build(BuildContext context) => ExplorerDialog(
    title: const Text('Create archive'),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'File name'),
            validator: (value) {
              final stem = archiveStem((value ?? '').trim());
              return stem.isEmpty ||
                      stem == '.' ||
                      stem == '..' ||
                      RegExp(r'[/\\\x00]').hasMatch(stem)
                  ? 'Enter a valid file name'
                  : null;
            },
          ),
          const SizedBox(height: 14),
          ExplorerDropdownField<String>(
            label: 'Format',
            value: format,
            options: const {'zip': 'ZIP', '7z': '7z'},
            onChanged: (value) => setState(() {
              format = value;
              name.text = '${archiveStem(name.text)}.$format';
            }),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: password,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Password (optional)',
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            onFieldSubmitted: (_) => create(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: create, child: const Text('Create')),
    ],
  );
}
