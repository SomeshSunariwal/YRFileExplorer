import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/network/presentation/connection_dialog.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';

class NetworkPage extends StatefulWidget {
  final AppSettings settings;
  final FileClipboard clipboard;
  final int? windowId;
  final Json? initialProfile;
  final String? initialProtocol;
  final String section;
  const NetworkPage({
    super.key,
    required this.settings,
    required this.clipboard,
    this.windowId,
    this.initialProfile,
    this.initialProtocol,
    this.section = 'Network',
  });
  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  bool searching = false, grid = false, scanning = false;
  List<Json> discovered = [];
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.settings.addListener(changed);
    if (widget.initialProfile != null || widget.initialProtocol != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => connect(
          widget.initialProfile ?? {'protocol': widget.initialProtocol},
        ),
      );
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.settings.removeListener(changed);
    search.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (widget.section == 'LAN') {
      await connect({'protocol': 'SMB'});
      return;
    }
    if (widget.section == 'WebDAV') {
      await connect({'protocol': 'WebDAV'});
      return;
    }
    final protocol = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Center(child: Text('New')),
        children: [
          for (final p
              in widget.section == 'FTP'
                  ? ['FTP', 'SFTP', 'FTPS']
                  : ['FTP', 'SFTP', 'FTPS', 'WebDAV', 'SMB'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, p),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(p == 'SMB' ? 'LAN' : p.toLowerCase()),
              ),
            ),
        ],
      ),
    );
    if (protocol != null && mounted) await connect({'protocol': protocol});
  }

  String credentialId(Json profile) =>
      '${profile['protocol']}|${profile['host']}|${profile['port']}|${profile['username']}';
  Future<void> connect(Json profile) async {
    if (profile['rememberPassword'] == true) {
      try {
        profile = {
          ...profile,
          'password':
              await Native.call<String>('connectionPassword', {
                'id': credentialId(profile),
              }) ??
              '',
        };
      } catch (e) {
        if (mounted) showError(context, e);
      }
      if (!mounted) return;
    }
    final p = await showDialog<Json>(
      context: context,
      builder: (_) => ConnectionDialog(profile: profile),
    );
    if (p == null || !mounted) return;
    final safe = Map<String, dynamic>.of(p)..remove('password');
    if (p['save'] == true) {
      await Native.call('saveConnectionPassword', {
        'id': credentialId(p),
        'password': p['rememberPassword'] == true ? p['password'] : '',
      });
      widget.settings.connections.removeWhere((e) => e['name'] == safe['name']);
      widget.settings.connections.add(safe);
      await widget.settings.save();
    }
    if (!mounted) return;
    ExplorerWorkspaceSession.instance.servers = widget.settings.connections;
    ExplorerWorkspaceSession.instance.openRemote(p);
    if (widget.windowId == null) Navigator.pop(context);
  }

  Future<void> remove(Json p) async {
    if (!await confirm(
      context,
      'Remove connection?',
      'Remove ${p['name']} from saved connections?',
      action: 'Remove',
    )) {
      return;
    }
    await Native.call('saveConnectionPassword', {
      'id': credentialId(p),
      'password': '',
    });
    widget.settings.connections.remove(p);
    await widget.settings.save();
  }

  Future<void> scan() async {
    if (scanning) return;
    setState(() => scanning = true);
    try {
      final servers = await Native.rows('lanScan');
      if (mounted) setState(() => discovered = servers);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.settings.connections
        .where(
          (p) =>
              [
                'SMB',
                'FTP',
                'SFTP',
                'FTPS',
                'WebDAV',
              ].contains(p['protocol']) &&
              '${p['name']} ${p['host']}'.toLowerCase().contains(
                search.text.toLowerCase(),
              ),
        )
        .toList();
    Widget profile(Json p) => ListTile(
      leading: Icon(
        p['protocol'] == 'SMB' ? Icons.computer : Icons.dns_outlined,
        color: primaryBlue,
      ),
      title: Text(p['name']),
      subtitle: Text('${p['protocol']} · ${p['host']}'),
      onTap: () => connect(p),
      trailing: IconButton(
        tooltip: 'Remove saved connection',
        onPressed: () => remove(p),
        icon: const Icon(Icons.more_vert),
      ),
    );
    return ExplorerPane(
      settings: widget.settings,
      windowId: widget.windowId,
      title: Text(widget.section),
      actions: [
        ExplorerAction(icon: Icons.add, label: 'New', onTap: create),
        ExplorerAction(
          icon: widget.section == 'FTP' || widget.section == 'WebDAV'
              ? Icons.search
              : Icons.radar,
          label: widget.section == 'FTP' || widget.section == 'WebDAV'
              ? 'Search'
              : 'Scan',
          onTap: widget.section == 'FTP' || widget.section == 'WebDAV'
              ? () => setState(() => searching = !searching)
              : scan,
        ),
        ExplorerAction(icon: Icons.refresh, label: 'Refresh', onTap: changed),
        ExplorerAction(
          icon: Icons.grid_view,
          label: 'View',
          onTap: () => setState(() => grid = !grid),
        ),
        ExplorerAction(
          icon: Icons.filter_none,
          label: 'Windows',
          onTap: () => showExplorerWindows(context),
        ),
      ],
      body: Column(
        children: [
          if (scanning) const LinearProgressIndicator(minHeight: 2),
          if (searching)
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: search,
                onChanged: (_) => changed(),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search connections',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Close search',
                    onPressed: () {
                      search.clear();
                      setState(() => searching = false);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                for (final group in ['LAN', 'FTP', 'WebDAV'].where(
                  (g) => widget.section == 'Network' || g == widget.section,
                ))
                  Builder(
                    builder: (_) {
                      final profiles = rows
                          .where(
                            (p) => group == 'LAN'
                                ? p['protocol'] == 'SMB'
                                : group == 'WebDAV'
                                ? p['protocol'] == 'WebDAV'
                                : [
                                    'FTP',
                                    'SFTP',
                                    'FTPS',
                                  ].contains(p['protocol']),
                          )
                          .toList();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          key: PageStorageKey('network-$group'),
                          initiallyExpanded: true,
                          title: Text('$group (${profiles.length})'),
                          children: [
                            if (profiles.isEmpty)
                              ListTile(
                                leading: const Icon(
                                  Icons.add_circle_outline,
                                  color: primaryBlue,
                                ),
                                title: const Text('New connection'),
                                onTap: () => group == 'LAN'
                                    ? connect({'protocol': 'SMB'})
                                    : group == 'WebDAV'
                                    ? connect({'protocol': 'WebDAV'})
                                    : create(),
                              ),
                            if (grid && profiles.isNotEmpty)
                              GridView.count(
                                crossAxisCount: 3,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  for (final p in profiles)
                                    InkWell(
                                      onTap: () => connect(p),
                                      onLongPress: () => remove(p),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            group == 'LAN'
                                                ? Icons.computer
                                                : Icons.dns_outlined,
                                            color: primaryBlue,
                                            size: 38,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            p['name'],
                                            maxLines: 2,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              )
                            else
                              ...profiles.map(profile),
                          ],
                        ),
                      );
                    },
                  ),
                if (discovered.isNotEmpty)
                  Card(
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      title: Text('Search Result (${discovered.length})'),
                      children: [
                        for (final server in discovered)
                          ListTile(
                            leading: const Icon(
                              Icons.computer,
                              color: primaryBlue,
                            ),
                            title: Text(server['host']),
                            subtitle: const Text('SMB file sharing'),
                            onTap: () => connect(server),
                          ),
                      ],
                    ),
                  ),
                if (widget.section == 'Network')
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.bluetooth, color: primaryBlue),
                      title: const Text('Bluetooth'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => ExplorerWorkspaceSession.instance.onTool
                          ?.call('bluetooth'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
