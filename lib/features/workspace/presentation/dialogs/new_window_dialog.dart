import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
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
  _WindowType('analysis', 'Storage Analyzer', Icons.pie_chart_outline),
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
  final primary =
      session.volumes.where((v) => v['removable'] != true).firstOrNull?['path']
          as String? ??
      session.root;
  switch (type) {
    case 'lan' || 'ftp' || 'bluetooth' || 'downloads':
      session.openPage(type);
    case 'http' || 'https':
      session.openPage('web', url: choice['path']);
    case 'samba':
      session.onServer?.call({
        'protocol': 'SMB',
        ...choice['profile'] as Map<String, dynamic>,
      });
    case 'file':
      session.open(choice['path']);
    case 'device':
      session.open(primary);
    case 'download':
      session.open('$primary/Download');
    case 'images' || 'music' || 'movies' || 'documents' || 'archives':
      final (category, title) = switch (type) {
        'images' => ('Images', 'Images'),
        'music' => ('Music', 'Music'),
        'movies' => ('Videos', 'Movies'),
        'documents' => ('Documents', 'Documents'),
        _ => ('Archives', 'Compressed'),
      };
      session.open(primary, category: category, title: title);
    case 'analysis':
      session.open(initial, page: 'analysis', title: 'Storage Analyzer');
    case 'apps' || 'trash':
      session.openPage(type);
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
  final typeAnchor = GlobalKey();
  bool pickerOpen = false;
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

  Future<void> pickType() async {
    FocusScope.of(context).unfocus();
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    if (!mounted) return;
    final anchor = typeAnchor.currentContext?.findRenderObject();
    final overlay = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    if (anchor is! RenderBox || overlay is! RenderBox) return;
    final rect =
        anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
    final below =
        (overlay.size.height -
                MediaQuery.paddingOf(context).bottom -
                rect.bottom -
                12)
            .clamp(48.0, 240.0);
    setState(() => pickerOpen = true);
    final value = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(rect.left, rect.bottom + 6, rect.width, 0),
        Offset.zero & overlay.size,
      ),
      constraints: BoxConstraints(
        minWidth: rect.width,
        maxWidth: rect.width,
        maxHeight: below,
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      popUpAnimationStyle: AnimationStyle(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        reverseDuration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      items: [
        for (final entry in _types)
          PopupMenuItem<String>(
            value: entry.id,
            height: 44,
            child: Row(
              children: [
                Icon(entry.icon, size: 18, color: primaryBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.label,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.id == type.id)
                  const Icon(Icons.check, size: 16, color: primaryBlue),
              ],
            ),
          ),
      ],
    );
    if (!mounted) return;
    setState(() => pickerOpen = false);
    select(value);
  }

  void create() {
    final value = path.text.trim();
    if (type.id == 'file' &&
        (value.isEmpty ||
            !ExplorerWorkspaceSession.instance.containsStoragePath(value))) {
      setState(() => error = 'Choose a folder in internal storage or SD card');
      return;
    }
    if (type.id == 'http' || type.id == 'https' || type.id == 'samba') {
      final uri = Uri.tryParse(value);
      final scheme = type.id == 'samba' ? 'smb' : type.id;
      if (uri == null ||
          uri.scheme != scheme ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        setState(
          () => error =
              'Enter a valid $scheme:// address without embedded credentials',
        );
        return;
      }
      if (type.id == 'samba') {
        final parts = uri.pathSegments
            .where((part) => part.isNotEmpty)
            .toList();
        Navigator.pop(context, <String, dynamic>{
          'type': type.id,
          'profile': {
            'host': uri.host,
            'port': '${uri.hasPort ? uri.port : 445}',
            'share': parts.isEmpty ? '' : parts.first,
            'path': parts.length < 2 ? '/' : '/${parts.skip(1).join('/')}',
            'name': uri.host,
          },
        });
        return;
      }
    }
    Navigator.pop(context, <String, dynamic>{'type': type.id, 'path': value});
  }

  @override
  Widget build(BuildContext context) => ExplorerDialog(
    contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
    title: const Text('New window'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: typeAnchor,
            onTap: pickType,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              isFocused: pickerOpen,
              decoration: InputDecoration(
                labelText: 'Type',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              child: Row(
                children: [
                  Icon(type.icon, color: primaryBlue, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      type.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  AnimatedRotation(
                    turns: pickerOpen ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: type.needsPath
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      key: ValueKey(type.id),
                      controller: path,
                      style: const TextStyle(fontSize: 14),
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: type.id == 'file'
                          ? TextInputType.text
                          : TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => create(),
                      onChanged: (_) {
                        if (error != null) setState(() => error = null);
                      },
                      decoration: InputDecoration(
                        labelText: 'Path',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        hintText: type.hint,
                        errorText: error,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: create,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Open'),
      ),
    ],
  );
}
