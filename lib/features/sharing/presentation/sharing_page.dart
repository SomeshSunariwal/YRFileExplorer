import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/sharing/application/sharing_session.dart';
import 'package:yr_file_explorer/features/sharing/presentation/sharing_dialogs.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_notice.dart';

class SharingPage extends StatefulWidget {
  final AppSettings settings;
  final int windowId;
  const SharingPage({
    super.key,
    required this.settings,
    required this.windowId,
  });
  @override
  State<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends State<SharingPage> {
  final session = SharingSession.instance;
  bool busy = false, startingScan = false;
  @override
  void initState() {
    super.initState();
    session.refresh();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> scan() => run(() async {
    setState(() => startingScan = true);
    try {
      await session.discover();
    } finally {
      if (mounted) setState(() => startingScan = false);
    }
  });

  Widget panel(BuildContext context, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .25),
      ),
    ),
    child: child,
  );
  @override
  Widget build(BuildContext context) => ExplorerPane(
    settings: widget.settings,
    windowId: widget.windowId,
    title: const Text('Sharing'),
    onActivate: session.refresh,
    actions: [
      ExplorerAction(
        icon: Icons.refresh,
        label: 'Refresh',
        onTap: () => run(session.refresh),
      ),
      ExplorerAction(
        icon: Icons.history_rounded,
        label: 'History',
        onTap: () =>
            ExplorerWorkspaceSession.instance.openPage('sharing_history'),
      ),
      ExplorerAction(
        icon: Icons.filter_none,
        label: 'Windows',
        onTap: () => showExplorerWindows(context),
      ),
    ],
    body: AnimatedBuilder(
      animation: Listenable.merge([session, widget.settings]),
      builder: (context, _) {
        final status = session.status;
        final hosting = status['hosting'] == true;
        final devices = session.devices;
        final networks = session.networks;
        final supported = status['supported'] != false;
        final scanning = startingScan || status['state'] == 'Searching';
        final scanned = status['state'] == 'Scan complete';
        final canStart = supported && !busy && !hosting && devices.isEmpty;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            14,
            14,
            14,
            ExplorerBottomBar.contentBottomPadding(context),
          ),
          children: [
            if (!supported)
              panel(
                context,
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Wi-Fi Direct is not available on this device. Use a compatible Android phone to create or join a network.',
                  ),
                ),
              ),
            panel(
              context,
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.wifi_tethering_rounded, color: primaryBlue),
                        SizedBox(width: 10),
                        Text(
                          'Share nearby',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Connect two phones directly over Wi-Fi. No internet or account needed.',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: canStart && !scanning && !scanned
                                ? () => run(session.create)
                                : null,
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('Create network'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: canStart && !scanning ? scan : null,
                            icon: const Icon(Icons.radar_rounded, size: 20),
                            label: const Text('Join network'),
                          ),
                        ),
                      ],
                    ),
                    if (busy && !startingScan)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
            if (hosting)
              panel(
                context,
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Your network code',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final digit
                              in (status['code'] as String? ?? '').split(''))
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryBlue.withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: primaryBlue.withValues(alpha: .3),
                                  ),
                                ),
                                child: Text(
                                  digit,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'On the other phone, open Sharing → Join network.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            if ((status['error'] as String? ?? session.loadError ?? '')
                .isNotEmpty)
              panel(
                context,
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    status['error'] as String? ?? session.loadError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (supported && !hosting && devices.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Available Networks',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (scanning && networks.isNotEmpty)
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Searching for nearby networks',
                        ),
                      ),
                  ],
                ),
              ),
              panel(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (networks.isEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 132),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox.square(
                                  dimension: 38,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: primaryBlue.withValues(
                                            alpha: .1,
                                          ),
                                        ),
                                        child: const SizedBox.expand(),
                                      ),
                                      if (scanning)
                                        const CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      const Icon(
                                        Icons.search_rounded,
                                        color: primaryBlue,
                                        size: 21,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  scanning
                                      ? 'Searching for nearby networks…'
                                      : scanned
                                      ? 'No nearby networks found. Tap Join network to try again.'
                                      : 'Tap Join network to find a nearby host.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    for (final network in networks)
                      ListTile(
                        leading: const Icon(
                          Icons.wifi_rounded,
                          color: primaryBlue,
                        ),
                        title: Text(network['name']),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: busy
                            ? null
                            : () async {
                                final joined = await showSharingCode(
                                  context,
                                  network,
                                );
                                if (joined && context.mounted) {
                                  showExplorerNotice(
                                    context,
                                    'Device connected',
                                    icon: Icons.link_rounded,
                                  );
                                }
                              },
                      ),
                  ],
                ),
              ),
            ],
            if (devices.isNotEmpty)
              panel(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Connected devices',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final peer in devices)
                      ListTile(
                        leading: const Icon(
                          Icons.phone_android_outlined,
                          color: primaryBlue,
                        ),
                        title: Text(peer['name']),
                        subtitle: const Text('Ready to receive files'),
                        trailing: const Icon(
                          Icons.check_circle_outline,
                          color: primaryBlue,
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Text(
                        'Select files in Device, then choose More → Send.',
                      ),
                    ),
                  ],
                ),
              ),
            if (hosting || devices.isNotEmpty || scanning || scanned)
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: busy ? null : () => run(session.stop),
                  icon: const Icon(Icons.link_off_rounded, size: 20),
                  label: Text(
                    scanning || scanned ? 'Stop discovery' : 'Disconnect',
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Keep the app open during transfers.\n'
                'Received files are saved in ${widget.settings.sharingReceiveFolderLabel}.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton.icon(
              onPressed: () => Native.call('sharingSettings'),
              icon: const Icon(Icons.wifi_rounded, size: 18),
              label: const Text('Wi-Fi settings'),
            ),
          ],
        );
      },
    ),
  );
}
