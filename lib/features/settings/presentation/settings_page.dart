import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

class SettingsPage extends StatelessWidget {
  final AppSettings settings;
  const SettingsPage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (_, child) => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(
                              'assets/branding/app_icon.png',
                              width: 52,
                              height: 52,
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
                                  'Version 1.0.0',
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
                const _Section('Files & storage'),
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
                const _Section('Privacy & about'),
                _SettingsCard(
                  children: [
                    const _InfoTile(
                      title: 'Privacy',
                      icon: Icons.verified_user_outlined,
                      text: 'No tracking. No advertising. No analytics, advertising identifiers, crash reporting, or telemetry SDKs. Network connections happen only for file operations you request.',
                    ),
                    const _InfoTile(
                      title: 'Passwords',
                      icon: Icons.key_outlined,
                      text: 'Connection passwords stay in memory unless you choose Remember password. Saved passwords are encrypted with Android Keystore. Encryption passwords are not stored.',
                    ),
                    const _InfoTile(
                      title: 'Android storage restrictions',
                      icon: Icons.lock_outline,
                      text: 'Android blocks other apps’ private data and most Android/data and Android/obb folders. All-files access does not unlock these paths. Folder analysis always includes hidden files.',
                    ),
                    _action(
                      'Open-source licenses',
                      null,
                      Icons.article_outlined,
                      () => showLicensePage(
                        context: context,
                        applicationName: 'YR File Explorer',
                        applicationVersion: '1.0.0',
                        applicationIcon: Image.asset(
                          'assets/branding/app_icon.png',
                          width: 72,
                          height: 72,
                        ),
                      ),
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
  ) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    secondary: _SettingsIcon(icon),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.4)),
    ),
    value: value,
    onChanged: changed,
  );

  Widget _action(
    String title,
    String? subtitle,
    IconData icon,
    VoidCallback action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    leading: _SettingsIcon(icon),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    subtitle: subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 12, height: 1.4),
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
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
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
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: primaryBlue.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 21, color: primaryBlue),
  );
}

class _InfoTile extends StatelessWidget {
  final String title, text;
  final IconData icon;
  const _InfoTile({
    required this.title,
    required this.text,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: _SettingsIcon(icon),
    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    childrenPadding: const EdgeInsets.fromLTRB(72, 0, 20, 18),
    children: [
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
