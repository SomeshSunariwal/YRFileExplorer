import 'package:flutter/material.dart';

import 'package:yr_file_explorer/app/theme/explorer_theme.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/features/workspace/presentation/workspace_page.dart';

class YRExplorer extends StatelessWidget {
  final AppSettings settings;
  const YRExplorer({super.key, required this.settings});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (_, child) => MaterialApp(
      title: 'YR File Explorer',
      debugShowCheckedModeBanner: false,
      theme: buildExplorerTheme(Brightness.light),
      darkTheme: buildExplorerTheme(Brightness.dark),
      themeMode: settings.dark ? ThemeMode.dark : ThemeMode.light,
      home: ExplorerWorkspace(settings: settings),
    ),
  );
}
