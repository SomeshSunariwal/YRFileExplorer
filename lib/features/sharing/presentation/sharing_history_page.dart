import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/files/presentation/open_explorer_file.dart';
import 'package:yr_file_explorer/features/sharing/application/sharing_session.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_progress_bar.dart';

class SharingHistoryPage extends StatefulWidget {
  final AppSettings settings;
  final int windowId;
  const SharingHistoryPage({
    super.key,
    required this.settings,
    required this.windowId,
  });
  @override
  State<SharingHistoryPage> createState() => _SharingHistoryPageState();
}

class _SharingHistoryPageState extends State<SharingHistoryPage> {
  final session = SharingSession.instance;
  bool openingFile = false;

  Future<void> openFile(BuildContext context, String path) async {
    if (openingFile) return;
    openingFile = true;
    try {
      final Map? properties;
      try {
        properties = await Native.call<Map>('properties', {'path': path});
      } on PlatformException {
        if (context.mounted) {
          showError(context, 'This file is no longer available at its saved location.');
        }
        return;
      }
      if (!context.mounted) return;
      if (properties == null ||
          properties['directory'] == true ||
          properties['readable'] != true) {
        showError(context, 'This file is no longer available at its saved location.');
        return;
      }
      await openExplorerFile(
        context,
        Map<String, dynamic>.from(properties),
        recycle: widget.settings.recycle,
      );
    } catch (error) {
      if (context.mounted) showError(context, error);
    } finally {
      openingFile = false;
    }
  }

  @override
  void initState() {
    super.initState();
    session.refresh();
  }

  @override
  Widget build(BuildContext context) => ExplorerPane(
    settings: widget.settings,
    windowId: widget.windowId,
    title: const Text('Sharing History'),
    onActivate: session.refresh,
    actions: [
      ExplorerAction(
        icon: Icons.wifi_tethering_rounded,
        label: 'Sharing',
        onTap: () => ExplorerWorkspaceSession.instance.openPage('sharing'),
      ),
      ExplorerAction(
        icon: Icons.delete_outline,
        label: 'Clear',
        onTap: () async {
          if (!await confirm(
            context,
            'Clear sharing history?',
            'Completed and failed entries will be removed. Received files will be kept.',
            action: 'Clear',
          )) {
            return;
          }
          await Native.call('sharingClearHistory');
          await session.refresh();
        },
      ),
      ExplorerAction(
        icon: Icons.filter_none,
        label: 'Windows',
        onTap: () => showExplorerWindows(context),
      ),
    ],
    body: AnimatedBuilder(
      animation: session,
      builder: (context, _) => session.history.isEmpty
          ? const EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: 'No transfers yet',
              message: 'Sent and received files will appear here with their progress.',
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                14,
                14,
                14,
                ExplorerBottomBar.contentBottomPadding(context),
              ),
              itemCount: session.history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final job = session.history[index];
                final bytes = (job['bytes'] as num).toInt(),
                    size = (job['size'] as num).toInt();
                final done = job['status'] == 'Completed';
                final path = job['path'] as String?;
                final canOpen = done && path != null && path.isNotEmpty;
                final fraction = size == 0
                    ? (done ? 1.0 : 0.0)
                    : (bytes / size).clamp(0.0, 1.0);
                return Material(
                  color: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor
                          .withValues(alpha: .3),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: canOpen ? () => openFile(context, path) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            job['direction'] == 'Sent'
                                ? Icons.north_east_rounded
                                : Icons.south_west_rounded,
                            color: primaryBlue,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              job['name'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(fraction * 100).floor()}%',
                            style: const TextStyle(
                              color: primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (canOpen) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      ExplorerProgressBar(value: fraction, height: 5),
                      const SizedBox(height: 7),
                      Text(
                        '${job['status']} · ${job['peer']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${sizeLabel(bytes)} / ${sizeLabel(size)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                      ),
                    ),
                  ),
                );
              },
            ),
    ),
  );
}
