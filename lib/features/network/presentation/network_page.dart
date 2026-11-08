import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_search_header.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
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
  bool searching = false, grid = false, scanning = false, scanned = false;
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
    Native.call('cancelLanScan');
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
      builder: (dialog) => ExplorerChoiceDialog(
        title: const Center(child: Text('New')),
        children: [
          for (final p
              in widget.section == 'FTP'
                  ? ['FTP', 'SFTP', 'FTPS']
                  : ['FTP', 'SFTP', 'FTPS', 'WebDAV', 'SMB'])
            ExplorerChoiceTile(
              icon: p == 'SMB'
                  ? Icons.computer_outlined
                  : p == 'WebDAV'
                  ? Icons.web_outlined
                  : p == 'SFTP' || p == 'FTPS'
                  ? Icons.lock_outline
                  : Icons.folder_shared_outlined,
              label: p == 'SMB' ? 'LAN' : p,
              onTap: () => Navigator.pop(dialog, p),
            ),
        ],
      ),
    );
    if (protocol != null && mounted) await connect({'protocol': protocol});
  }

  String credentialId(Json profile) =>
      '${profile['protocol']}|${profile['host']}|${profile['port']}|${profile['username']}';
  Future<void> connect(Json profile, {bool edit = false}) async {
    try {
      if (profile['rememberPassword'] == true) {
        profile = {
          ...profile,
          'password':
              await Native.call<String>('connectionPassword', {
                'id': credentialId(profile),
              }) ??
              '',
        };
      }
      if (!mounted) return;
      final saved = widget.settings.connections.any(
        (p) =>
            identical(p, profile) ||
            (credentialId(p) == credentialId(profile) &&
                p['name'] == profile['name']),
      );
      Json? p;
      if (saved &&
          !edit &&
          (profile['rememberPassword'] == true ||
              profile['anonymous'] == true)) {
        p = profile;
      } else {
        p = await showDialog<Json>(
          context: context,
          builder: (_) => ConnectionDialog(profile: profile),
        );
      }
      if (p == null || !mounted) return;
      final safe = Map<String, dynamic>.of(p)..remove('password');
      if (p['save'] == true) {
        await Native.call('saveConnectionPassword', {
          'id': credentialId(p),
          'password': p['rememberPassword'] == true ? p['password'] : '',
        });
        if (saved && credentialId(profile) != credentialId(p)) {
          await Native.call('saveConnectionPassword', {
            'id': credentialId(profile),
            'password': '',
          });
        }
        widget.settings.connections.removeWhere(
          (old) =>
              (credentialId(old) == credentialId(profile) &&
                  old['name'] == profile['name']) ||
              (credentialId(old) == credentialId(p!) &&
                  old['name'] == safe['name']),
        );
        widget.settings.connections.add(safe);
        await widget.settings.save();
      }
      if (!mounted) return;
      ExplorerWorkspaceSession.instance.servers = widget.settings.connections;
      final workspace = ExplorerWorkspaceSession.instance;
      final split = workspace.windows.any(
        (window) => window.id == widget.windowId && window.split,
      );
      workspace.openRemote(p);
      if (split && workspace.activeId != null) {
        if (widget.windowId != null) {
          workspace.setSplit(widget.windowId!, false);
        }
        workspace.setSplit(workspace.activeId!, true);
      }
      if (widget.windowId == null) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
    if (scanning) {
      await Native.call('cancelLanScan');
      return;
    }
    setState(() => scanning = true);
    try {
      final servers = await Native.rows('lanScan');
      if (mounted) {
        setState(() {
          discovered = servers;
          scanned = true;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Widget iconBadge(IconData icon) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: primaryBlue.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 20, color: primaryBlue),
  );

  Widget sectionTitle(String label, IconData icon, int count) => Row(
    children: [
      iconBadge(icon),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: primaryBlue.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            fontSize: 11,
            color: primaryBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  Widget panel(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    ),
  );

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
    Widget profile(Json p) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: .5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          minTileHeight: 56,
          contentPadding: const EdgeInsets.only(left: 12, right: 2),
          leading: iconBadge(
            p['protocol'] == 'SMB'
                ? Icons.computer_outlined
                : Icons.dns_outlined,
          ),
          title: Text(
            p['name'],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${p['protocol']} · ${p['host']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () => connect(p),
          trailing: PopupMenuButton<String>(
            tooltip: 'Connection actions',
            onSelected: (action) =>
                action == 'edit' ? connect(p, edit: true) : remove(p),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit connection')),
              PopupMenuItem(value: 'remove', child: Text('Remove connection')),
            ],
          ),
        ),
      ),
    );
    return ExplorerPane(
      busy: scanning,
      interceptBack: searching,
      onBack: searching
          ? () {
              search.clear();
              setState(() => searching = false);
            }
          : null,
      searchHeader: searching
          ? ExplorerSearchHeader(
              controller: search,
              hint: 'Search connections',
              onChanged: (_) => setState(() {}),
              onClose: () {
                search.clear();
                setState(() => searching = false);
              },
            )
          : null,
      settings: widget.settings,
      windowId: widget.windowId,
      title: Text(widget.section),
      actions: [
        ExplorerAction(icon: Icons.add, label: 'New', onTap: create),
        ExplorerAction(
          icon: widget.section == 'FTP' || widget.section == 'WebDAV'
              ? Icons.search
              : scanning
              ? Icons.stop
              : Icons.radar,
          label: widget.section == 'FTP' || widget.section == 'WebDAV'
              ? 'Search'
              : scanning
              ? 'Stop'
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
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                ExplorerBottomBar.contentBottomPadding(context),
              ),
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
                      return panel(
                        ExpansionTile(
                          key: PageStorageKey('network-$group'),
                          initiallyExpanded: true,
                          minTileHeight: 48,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          title: sectionTitle(group, switch (group) {
                            'LAN' => Icons.computer_outlined,
                            'FTP' => Icons.folder_shared_outlined,
                            _ => Icons.public,
                          }, profiles.length),
                          children: [
                            if (grid && profiles.isNotEmpty)
                              GridView.count(
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                mainAxisExtent: 96,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  8,
                                ),
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  for (final p in profiles)
                                    InkWell(
                                      onTap: () => connect(p),
                                      onLongPress: () => remove(p),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Ink(
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerLow,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
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
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            else
                              ...profiles.map(profile),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                              child: Material(
                                color: primaryBlue.withValues(alpha: .07),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: primaryBlue.withValues(alpha: .18),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => group == 'LAN'
                                      ? connect({'protocol': 'SMB'})
                                      : group == 'WebDAV'
                                      ? connect({'protocol': 'WebDAV'})
                                      : create(),
                                  child: const SizedBox(
                                    height: 44,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_circle_outline,
                                          size: 19,
                                          color: primaryBlue,
                                        ),
                                        SizedBox(width: 9),
                                        Text(
                                          'New connection',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                if (scanned)
                  panel(
                    ExpansionTile(
                      initiallyExpanded: true,
                      title: sectionTitle(
                        'Scan results',
                        Icons.radar,
                        discovered.length,
                      ),
                      minTileHeight: 56,
                      children: [
                        if (discovered.isEmpty)
                          const ListTile(
                            title: Text('No SMB servers found'),
                            subtitle: Text(
                              'You can still add a server by its address.',
                            ),
                          ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
