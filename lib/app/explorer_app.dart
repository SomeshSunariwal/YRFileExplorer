import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/theme/explorer_scroll_behavior.dart';

import 'package:yr_file_explorer/app/theme/explorer_theme.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/features/workspace/presentation/workspace_page.dart';
import 'package:yr_file_explorer/features/storage/presentation/storage_permission_gate.dart';

class YRExplorer extends StatelessWidget {
  static final _lightTheme = buildExplorerTheme(Brightness.light);
  static final _darkTheme = buildExplorerTheme(Brightness.dark);
  final AppSettings settings;
  const YRExplorer({super.key, required this.settings});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (_, child) => MaterialApp(
      title: 'YR File Explorer',
      scrollBehavior: const ExplorerScrollBehavior(),
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: settings.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => TooltipVisibility(
        visible: false,
        child: StoragePermissionGate(child: child ?? const SizedBox.shrink()),
      ),
      home: ExplorerWorkspace(settings: settings),
    ),
  );
}
