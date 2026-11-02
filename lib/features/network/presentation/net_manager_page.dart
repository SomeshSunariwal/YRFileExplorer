import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';

class NetManagerPage extends StatefulWidget {
  final AppSettings settings;
  final int? windowId;
  const NetManagerPage({super.key, required this.settings, this.windowId});
  @override
  State<NetManagerPage> createState() => _NetManagerPageState();
}

class _NetManagerPageState extends State<NetManagerPage>
    with WidgetsBindingObserver {
  Json? data;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    try {
      final info = Map<String, dynamic>.from(
        (await Native.call<Map>('networkInfo'))!,
      );
      if (mounted) {
        setState(() {
          data = info;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ExplorerPane(
    settings: widget.settings,
    windowId: widget.windowId,
    title: const Text('Net Manager'),
    actions: [
      ExplorerAction(
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: () => Native.call('networkSettings'),
      ),
      ExplorerAction(
        icon: Icons.wifi_tethering,
        label: 'Hotspot',
        onTap: () => Native.call('hotspotSettings'),
      ),
      ExplorerAction(icon: Icons.refresh, label: 'Refresh', onTap: load),
      ExplorerAction(
        icon: Icons.filter_none,
        label: 'Windows',
        onTap: () => showExplorerWindows(context),
      ),
    ],
    body: error != null
        ? EmptyState(title: 'Network status unavailable', message: error!)
        : data == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              ExplorerBottomBar.contentBottomPadding(context),
            ),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        data!['connected'] == true
                            ? Icons.wifi
                            : Icons.wifi_off,
                        size: 64,
                        color: primaryBlue,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        data!['type'],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => Native.call('networkSettings'),
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Manage connection'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final entry in [
                      ('Interface', data!['interface']),
                      ('IP address', (data!['addresses'] as List).join('\n')),
                      ('Gateway', (data!['gateways'] as List).join('\n')),
                      ('DNS', (data!['dns'] as List).join('\n')),
                      ('MTU', '${data!['mtu']}'),
                      ('Metered', data!['metered'] == true ? 'Yes' : 'No'),
                    ])
                      ListTile(
                        title: Text(
                          entry.$1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        subtitle: SelectableText(
                          entry.$2.toString().isEmpty
                              ? '—'
                              : entry.$2.toString(),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
  );
}
