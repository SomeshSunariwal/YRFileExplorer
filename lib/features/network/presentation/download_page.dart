import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final url = TextEditingController(),
      name = TextEditingController(),
      folder = TextEditingController(text: '/storage/emulated/0/Download');
  bool busy = false;
  @override
  void dispose() {
    url.dispose();
    name.dispose();
    folder.dispose();
    super.dispose();
  }

  Future<void> download() async {
    setState(() => busy = true);
    try {
      await Native.call('download', {
        'url': url.text.trim(),
        'name': name.text.trim(),
        'path': folder.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Download started. Follow progress in Android notifications.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Download Manager')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.download_outlined, size: 72, color: primaryBlue),
        const SizedBox(height: 24),
        TextField(
          controller: url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'HTTP / HTTPS URL'),
          onChanged: (v) {
            final u = Uri.tryParse(v);
            if (u != null && u.pathSegments.isNotEmpty) {
              name.text = u.pathSegments.last;
            }
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'File name'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: folder,
          decoration: const InputDecoration(labelText: 'Destination folder'),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : download,
          icon: const Icon(Icons.download),
          label: const Text('Download'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Downloads are handled by Android and continue when you leave this screen. Existing files are never overwritten.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    ),
  );
}
