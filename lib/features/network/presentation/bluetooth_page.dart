import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/storage/presentation/pickers/local_file_picker.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';

class BluetoothPage extends StatefulWidget {
  final AppSettings settings;
  final FileClipboard clipboard;
  final int? windowId;
  const BluetoothPage({
    super.key,
    required this.settings,
    required this.clipboard,
    this.windowId,
  });
  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage>
    with WidgetsBindingObserver {
  Json? info;
  String? error;
  bool scanning = false;
  final devices = <String, Json>{};
  StreamSubscription<Json>? events;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    events = Native.events.listen((e) {
      if (!mounted) return;
      if (e['type'] == 'bluetoothDevice') {
        final device = Map<String, dynamic>.from(e['device']);
        setState(() => devices[device['address']] = device);
      }
      if (e['type'] == 'bluetoothScanDone') setState(() => scanning = false);
    }, onError: (_) {});
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    events?.cancel();
    Native.call('bluetoothStop');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    try {
      final result = Map<String, dynamic>.from(
        (await Native.call<Map>('bluetoothInfo'))!,
      );
      if (mounted) {
        setState(() {
          info = result;
          error = null;
          for (final device in jsonRows(result['devices'])) {
            devices[device['address']] = device;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> scan() async {
    try {
      await load();
      if (info?['supported'] != true) return;
      if (info?['permission'] != true || info?['scanPermission'] != true) {
        await Native.call('requestBluetooth');
        await load();
        if (info?['permission'] != true || info?['scanPermission'] != true) {
          return;
        }
      }
      if (info?['enabled'] != true) {
        await Native.call('bluetoothSettings');
        return;
      }
      setState(() => scanning = true);
      await Native.call('bluetoothScan');
    } catch (e) {
      if (mounted) {
        setState(() => scanning = false);
        showError(context, e);
      }
    }
  }

  Future<void> send() async {
    final files = await pickLocalFiles(
      context,
      root: ExplorerWorkspaceSession.instance.root,
      initial: widget.clipboard.paths,
    );
    if (files != null && files.isNotEmpty) {
      try {
        await Native.call('share', {'paths': files});
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  Future<void> open(Json device) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bluetooth, color: primaryBlue),
              title: Text(device['name']),
              subtitle: Text(device['address']),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Browse files'),
              onTap: () => Navigator.pop(sheet, 'browse'),
            ),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Send files'),
              onTap: () => Navigator.pop(sheet, 'send'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Pairing settings'),
              onTap: () => Navigator.pop(sheet, 'settings'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'send') await send();
    if (choice == 'settings') await Native.call('bluetoothSettings');
    if (choice == 'browse') {
      ExplorerWorkspaceSession.instance.openRemote({
        'protocol': 'Bluetooth',
        'host': device['address'],
        'name': device['name'],
        'path': '/',
      });
    }
  }

  @override
  Widget build(BuildContext context) => ExplorerPane(
    busy: scanning,
    settings: widget.settings,
    windowId: widget.windowId,
    title: const Text('Bluetooth'),
    actions: [
      ExplorerAction(
        icon: Icons.add,
        label: 'New',
        onTap: () => Native.call('bluetoothSettings'),
      ),
      ExplorerAction(
        icon: scanning ? Icons.stop : Icons.radar,
        label: scanning ? 'Stop' : 'Scan',
        onTap: scanning
            ? () {
                Native.call('bluetoothStop');
                setState(() => scanning = false);
              }
            : scan,
      ),
      ExplorerAction(icon: Icons.refresh, label: 'Refresh', onTap: load),
      ExplorerAction(icon: Icons.send_outlined, label: 'Send', onTap: send),
      ExplorerAction(
        icon: Icons.filter_none,
        label: 'Windows',
        onTap: () => showExplorerWindows(context),
      ),
    ],
    body: Column(
      children: [
        Expanded(
          child: error != null
              ? EmptyState(title: 'Bluetooth unavailable', message: error!)
              : info == null
              ? const Center(child: CircularProgressIndicator())
              : info!['supported'] != true
              ? const EmptyState(
                  icon: Icons.bluetooth_disabled,
                  title: 'Bluetooth is not available',
                  message: 'This device has no Bluetooth adapter.',
                )
              : info!['permission'] != true
              ? EmptyState(
                  icon: Icons.bluetooth,
                  title: 'Nearby devices',
                  message:
                      'Allow access to find and connect to Bluetooth devices.',
                  action: FilledButton(
                    onPressed: scan,
                    child: const Text('Allow nearby devices'),
                  ),
                )
              : info!['enabled'] != true
              ? EmptyState(
                  icon: Icons.bluetooth_disabled,
                  title: 'Bluetooth is off',
                  message: 'Turn on Bluetooth to connect to nearby devices.',
                  action: FilledButton(
                    onPressed: () => Native.call('bluetoothSettings'),
                    child: const Text('Turn on'),
                  ),
                )
              : devices.isEmpty
              ? EmptyState(
                  icon: Icons.bluetooth_searching,
                  title: scanning ? 'Searching…' : 'No paired devices',
                  message: 'Make the other device discoverable, then scan.',
                  action: TextButton(
                    onPressed: scan,
                    child: const Text('Scan'),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.only(
                    bottom: ExplorerBottomBar.contentBottomPadding(context),
                  ),
                  children: [
                    for (final device in devices.values)
                      ListTile(
                        leading: const Icon(
                          Icons.bluetooth,
                          color: primaryBlue,
                        ),
                        title: Text(device['name']),
                        subtitle: Text(
                          '${device['address']} · ${device['bonded'] == true ? 'Paired' : 'Available'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(device),
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}
