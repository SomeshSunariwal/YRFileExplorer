import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

Future<void> showStorageLocations(
  BuildContext context, {
  void Function(String)? onSelect,
}) {
  final session = ExplorerWorkspaceSession.instance;
  var listing = Native.rows('volumes');
  void open(BuildContext dialog, String path) {
    Navigator.pop(dialog);
    if (onSelect != null) {
      onSelect(path);
    } else {
      session.open(path);
    }
  }

  return showDialog<void>(
    context: context,
    builder: (dialog) {
      final dark = Theme.of(dialog).brightness == Brightness.dark;
      final line = dark ? Colors.white12 : const Color(0xffe8edf1);
      return ExplorerDialogSurface(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.sizeOf(dialog).height * .68,
          ),
          child: StatefulBuilder(
            builder: (dialog, update) {
              Widget location({
                required String label,
                required IconData icon,
                required VoidCallback onTap,
                String? detail,
                String? path,
              }) => InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 23, color: primaryBlue),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (detail != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  detail,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: dark
                                        ? Colors.white60
                                        : const Color(0xff77838e),
                                  ),
                                ),
                              ),
                            if (path != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExplorerDialogHeader(title: Text('History')),
                  Flexible(
                    child: FutureBuilder<List<Json>>(
                      future: listing,
                      initialData: session.volumes.isEmpty
                          ? null
                          : session.volumes,
                      builder: (dialog, snapshot) {
                        if (snapshot.hasError && !snapshot.hasData) {
                          return Padding(
                            padding: const EdgeInsets.all(20),
                            child: TextButton.icon(
                              onPressed: () => update(
                                () => listing = Native.rows('volumes'),
                              ),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry loading storage'),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final volumes = snapshot.data!;
                        session.volumes = volumes;
                        final recent = session.history
                            .where(
                              (p) =>
                                  session.containsStoragePath(p) &&
                                  !volumes.any((v) => v['path'] == p),
                            )
                            .toList();
                        return ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            for (final volume in volumes) ...[
                              Divider(height: 1, indent: 57, color: line),
                              location(
                                label: volume['primary'] == false
                                    ? volume['name']
                                    : 'Device',
                                icon: volume['primary'] == false
                                    ? Icons.sd_card_outlined
                                    : Icons.phone_android_outlined,
                                detail:
                                    '${sizeLabel(((volume['total'] as num? ?? 0) - (volume['free'] as num? ?? 0)).clamp(0, double.infinity))} used / ${sizeLabel(volume['total'] ?? 0)}',
                                onTap: () => open(dialog, volume['path']),
                              ),
                            ],
                            if (recent.isNotEmpty) ...[
                              Divider(height: 1, color: line),
                              for (final path in recent)
                                location(
                                  label: baseName(path),
                                  path: path,
                                  icon: Icons.history,
                                  onTap: () => open(dialog, path),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  Divider(height: 1, color: line),
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        shape: const RoundedRectangleBorder(),
                        foregroundColor: primaryBlue,
                      ),
                      onPressed: () => update(() => session.history.clear()),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text(
                        'Clear',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
