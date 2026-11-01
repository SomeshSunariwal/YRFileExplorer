import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';

class TransferPage extends StatefulWidget {
  final String path;
  const TransferPage({super.key, this.path = '/storage/emulated/0/Download'});
  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage>
    with WidgetsBindingObserver {
  late final TextEditingController folder;
  Json? session;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    folder = TextEditingController(text: widget.path);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Native.call('transferStop');
    folder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && session != null) stop();
  }

  Future<void> start() async {
    setState(() => busy = true);
    try {
      final s = await Native.call<Map>('transferStart', {'path': folder.text});
      if (mounted) setState(() => session = Map<String, dynamic>.from(s!));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    await Native.call('transferStop');
    if (mounted) setState(() => session = null);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('View on PC · Wi-Fi Transfer')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.phonelink, size: 88, color: primaryBlue),
        const SizedBox(height: 20),
        Text(
          'Transfer files over Wi-Fi',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'Connect your computer and phone to the same trusted network. Open the session URL in your computer’s browser to download or upload files.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        TextField(
          controller: folder,
          enabled: session == null,
          decoration: const InputDecoration(
            labelText: 'Folder to share',
            prefixIcon: Icon(Icons.folder_outlined),
          ),
        ),
        const SizedBox(height: 16),
        if (session == null)
          FilledButton.icon(
            onPressed: busy ? null : start,
            icon: const Icon(Icons.play_arrow),
            label: Text(busy ? 'Starting…' : 'Start'),
          )
        else ...[
          const Text(
            'Open this URL on your computer:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final url in session!['urls'] as List)
            Card(
              child: ListTile(
                title: SelectableText(
                  url,
                  style: const TextStyle(fontSize: 13, color: primaryBlue),
                ),
                trailing: IconButton(
                  tooltip: 'Copy session URL',
                  onPressed: () => Clipboard.setData(ClipboardData(text: url)),
                  icon: const Icon(Icons.copy),
                ),
              ),
            ),
          if ((session!['urls'] as List).isEmpty)
            const Text(
              'No local network address found. Connect to Wi-Fi and restart the transfer.',
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop transfer'),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Anyone with this session URL can access the selected folder. Transfers use HTTP on your local network. Keep this screen open; leaving the app stops the server.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    ),
  );
}
