import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

class _WindowType {
  final String id, label;
  final IconData icon;
  final String? hint;
  final bool network;
  const _WindowType(
    this.id,
    this.label,
    this.icon, {
    this.hint,
    this.network = false,
  });
  bool get needsPath => hint != null;
}

const _types = [
  _WindowType('device', 'Device', Icons.phone_android_outlined),
  _WindowType('sdcard', 'Sdcard', Icons.sd_storage_outlined),
  _WindowType('images', 'Images', Icons.image_outlined),
  _WindowType('music', 'Music', Icons.music_note_outlined),
  _WindowType('movies', 'Movies', Icons.movie_outlined),
  _WindowType('documents', 'Documents', Icons.description_outlined),
  _WindowType('apps', 'APP', Icons.android_rounded),
  _WindowType('download', 'Download', Icons.download_outlined),
  _WindowType('archives', 'Compressed', Icons.folder_zip_outlined),
  _WindowType('lan', 'LAN', Icons.computer_outlined, network: true),
  _WindowType('ftp', 'FTP', Icons.dns_outlined, network: true),
  _WindowType('bluetooth', 'Bluetooth', Icons.bluetooth, network: true),
  _WindowType(
    'downloads',
    'Download Manager',
    Icons.downloading_outlined,
    network: true,
  ),
  _WindowType('analysis', 'SD Card Analyst', Icons.pie_chart_outline),
  _WindowType('trash', 'Recycle Bin', Icons.delete_outline),
  _WindowType(
    'http',
    'http (Web)',
    Icons.public,
    hint: 'http://example.com',
    network: true,
  ),
  _WindowType(
    'file',
    'file (Local)',
    Icons.folder_outlined,
    hint: '/storage/emulated/0',
  ),
  _WindowType(
    'https',
    'https (Web)',
    Icons.lock_outline,
    hint: 'https://example.com',
    network: true,
  ),
  _WindowType(
    'samba',
    'samba (LAN)',
    Icons.lan_outlined,
    hint: 'smb://server/share',
    network: true,
  ),
];

Future<void> showNewExplorerWindow(BuildContext context) async {
  final session = ExplorerWorkspaceSession.instance;
  final current = session.windows
      .where((w) => w.id == session.activeId && w.profile == null)
      .firstOrNull;
  final initial = current == null
      ? session.root
      : current.page == 'archive'
      ? parentPath(current.path)
      : current.path;
  final choice = await showDialog<Json>(
    context: context,
    builder: (_) => _NewWindowDialog(initialPath: initial),
  );
  if (choice == null || !context.mounted) return;
  final type = choice['type'] as String;
  // Network choices are presentation-only until network work resumes.
  if (_types.firstWhere((entry) => entry.id == type).network) return;
  final primary =
      session.volumes.where((v) => v['removable'] != true).firstOrNull?['path']
          as String? ??
      session.root;
  switch (type) {
    case 'file':
      session.open(choice['path'], reuse: false);
    case 'device':
      session.open(primary, reuse: false);
    case 'sdcard':
      final volume = session.volumes
          .where((v) => v['removable'] == true)
          .firstOrNull;
      session.open(volume?['path'] ?? primary, reuse: false);
    case 'download':
      session.open('$primary/Download', reuse: false);
    case 'images' || 'music' || 'movies' || 'documents' || 'archives':
      final (category, title) = switch (type) {
        'images' => ('Images', 'Images'),
        'music' => ('Music', 'Music'),
        'movies' => ('Videos', 'Movies'),
        'documents' => ('Documents', 'Documents'),
        _ => ('Archives', 'Compressed'),
      };
      session.open(primary, category: category, title: title, reuse: false);
    case 'analysis':
      session.open(
        initial,
        page: 'analysis',
        title: 'SD Card Analyst',
        reuse: false,
      );
    case 'apps' || 'trash':
      session.openPage(type, reuse: false);
  }
}

class _NewWindowDialog extends StatefulWidget {
  final String initialPath;
  const _NewWindowDialog({required this.initialPath});
  @override
  State<_NewWindowDialog> createState() => _NewWindowDialogState();
}

class _NewWindowDialogState extends State<_NewWindowDialog> {
  final path = TextEditingController();
  final drafts = <String, String>{};
  _WindowType type = _types.first;
  String? error;
  @override
  void initState() {
    super.initState();
    drafts['file'] = widget.initialPath;
  }

  @override
  void dispose() {
    path.dispose();
    super.dispose();
  }

  void select(String? value) {
    if (value == null) return;
    FocusScope.of(context).unfocus();
    drafts[type.id] = path.text;
    setState(() {
      type = _types.firstWhere((t) => t.id == value);
      path.text = drafts[type.id] ?? '';
      error = null;
    });
  }

  void create() {
    if (type.network) return;
    final value = path.text.trim();
    if (type.needsPath &&
        (value.isEmpty ||
            !ExplorerWorkspaceSession.instance.containsStoragePath(value))) {
      setState(() => error = 'Choose a folder in internal storage or SD card');
      return;
    }
    Navigator.pop(context, <String, dynamic>{'type': type.id, 'path': value});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    scrollable: true,
    title: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: primaryBlue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.tab_outlined, color: primaryBlue, size: 24),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'New window',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose what to open.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: type.id,
            isExpanded: true,
            menuMaxHeight: 320,
            borderRadius: BorderRadius.circular(16),
            decoration: InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            items: [
              for (final entry in _types)
                DropdownMenuItem(
                  value: entry.id,
                  child: Row(
                    children: [
                      Icon(entry.icon, color: primaryBlue, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: select,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: type.needsPath
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextField(
                      key: ValueKey(type.id),
                      controller: path,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: type.id == 'file'
                          ? TextInputType.text
                          : TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: type.network ? null : (_) => create(),
                      onChanged: (_) {
                        if (error != null) setState(() => error = null);
                      },
                      decoration: InputDecoration(
                        labelText: 'Path',
                        hintText: type.hint,
                        errorText: error,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (type.network)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Network windows are currently unavailable.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    ),
    actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: type.network ? null : create,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Open'),
      ),
    ],
  );
}
