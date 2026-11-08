import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/storage/presentation/pickers/local_directory_picker.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';

class SettingsPage extends StatelessWidget {
  final AppSettings settings;
  const SettingsPage({super.key, required this.settings});

  Future<void> chooseReceiveFolder(BuildContext context) async {
    try {
      final defaultPath = await Native.call<String>(
        'sharingDefaultReceiveFolder',
      );
      final volumes = await Native.rows('volumes');
      final primaryPath =
          volumes
                  .where((volume) => volume['removable'] != true)
                  .firstOrNull?['path']
              as String?;
      final current = settings.sharingReceiveFolder ?? defaultPath;
      final initialPath = current != null && await Directory(current).exists()
          ? current
          : primaryPath ?? '/storage/emulated/0';
      if (!context.mounted) return;
      final path = await chooseLocalDirectory(
        context,
        initialPath: initialPath,
        hidden: settings.hidden,
        volumes: volumes,
        defaultPath: settings.sharingReceiveFolder == null ? null : defaultPath,
      );
      if (path == null || !context.mounted) return;
      settings.sharingReceiveFolder = path == defaultPath
          ? null
          : await Native.call<String>('sharingValidateReceiveFolder', {
                  'path': path,
                }) ??
                (throw StateError('The receive folder could not be saved.'));
      await settings.save();
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (_, child) => Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Transform.translate(
          offset: const Offset(-11, 0),
          child: const Text('Settings'),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                24 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                _SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(
                              'assets/branding/app_icon.png',
                              width: 44,
                              height: 44,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YR File Explorer',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Version 1.0.1',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const _Section('Appearance'),
                _SettingsCard(
                  children: [
                    _toggle(
                      'Dark theme',
                      'Use a charcoal colour palette',
                      Icons.dark_mode_outlined,
                      settings.dark,
                      (v) {
                        settings.dark = v;
                        settings.save();
                      },
                    ),
                    _toggle(
                      'Grid view',
                      'Display files as a grid of icons',
                      Icons.grid_view_rounded,
                      settings.grid,
                      (v) {
                        settings.grid = v;
                        settings.viewMode = v ? 'Medium Icon' : 'Medium Detail';
                        settings.save();
                      },
                    ),
                  ],
                ),
                const _Section('Files & sharing'),
                _SettingsCard(
                  children: [
                    _toggle(
                      'Show hidden files',
                      'Include hidden items when browsing',
                      Icons.visibility_outlined,
                      settings.hidden,
                      (v) {
                        settings.hidden = v;
                        settings.save();
                      },
                    ),
                    _toggle(
                      'Show folder sizes',
                      'Calculate folder sizes and item counts',
                      Icons.data_usage_outlined,
                      settings.folderSizes,
                      (v) {
                        settings.folderSizes = v;
                        settings.save();
                      },
                    ),
                    _toggle(
                      'Recycle Bin',
                      'Keep deleted files until you empty the bin',
                      Icons.delete_outline,
                      settings.recycle,
                      (v) {
                        settings.recycle = v;
                        settings.save();
                      },
                    ),
                    _action(
                      'Received files location',
                      settings.sharingReceiveFolderLabel,
                      Icons.folder_open_outlined,
                      () => chooseReceiveFolder(context),
                    ),
                  ],
                ),
                const _Section('Music'),
                _SettingsCard(
                  children: [
                    _toggle(
                      'Background playback',
                      'Keep music playing after leaving the player',
                      Icons.headphones_outlined,
                      settings.backgroundPlayback,
                      (v) async {
                        settings.backgroundPlayback = v;
                        await settings.save();
                        if (!v) await Native.call('stopMusic');
                      },
                    ),
                  ],
                ),
                const _Section('Permissions'),
                _SettingsCard(
                  children: [
                    _action(
                      'Storage access',
                      'Manage access to files on this device',
                      Icons.folder_open_outlined,
                      () => Native.call('requestPermission'),
                    ),
                    _action(
                      'APK installation access',
                      'Manage permission to install apps',
                      Icons.install_mobile_outlined,
                      () => Native.call('installPermission'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _toggle(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> changed,
  ) => MergeSemantics(
    child: Builder(
      builder: (context) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return ListTile(
          dense: true,
          minTileHeight: 56,
          minLeadingWidth: 36,
          horizontalTitleGap: 12,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: _SettingsIcon(icon),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 11.5, height: 1.25),
            ),
          ),
          onTap: () => changed(!value),
          trailing: SizedBox(
            height: 44,
            child: CupertinoSwitch(
              value: value,
              onChanged: changed,
              activeTrackColor: primaryBlue,
              inactiveTrackColor: dark ? const Color(0xff3b3b3b) : Colors.white,
              thumbColor: Colors.white,
              trackOutlineColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? primaryBlue
                    : dark
                    ? const Color(0xff62676c)
                    : const Color(0xffbac1c6),
              ),
              trackOutlineWidth: const WidgetStatePropertyAll(1.2),
            ),
          ),
        );
      },
    ),
  );

  Widget _action(
    String title,
    String? subtitle,
    IconData icon,
    VoidCallback action,
  ) => ListTile(
    dense: true,
    minTileHeight: 56,
    minLeadingWidth: 36,
    horizontalTitleGap: 12,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    leading: _SettingsIcon(icon),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    subtitle: subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 11.5, height: 1.25),
            ),
          ),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: action,
  );
}

class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: .3,
      ),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: explorerLine(context).withValues(alpha: .75)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: .5,
              indent: 72,
              endIndent: 16,
              color: explorerLine(context),
            ),
          children[i],
        ],
      ],
    ),
  );
}

class _SettingsIcon extends StatelessWidget {
  final IconData icon;
  const _SettingsIcon(this.icon);
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: primaryBlue.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 20, color: primaryBlue),
  );
}
