import 'package:flutter/material.dart';

import 'package:yr_file_explorer/app/explorer_app.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(YRExplorer(settings: settings));
}
