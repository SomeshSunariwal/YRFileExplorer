import 'package:flutter/material.dart';
import 'package:yr_file_explorer/features/analysis/presentation/sd_card_analyst_page.dart';
import 'package:yr_file_explorer/features/analysis/presentation/storage_analysis_page.dart';
import 'package:yr_file_explorer/features/analysis/presentation/analysis_results_page.dart';
import 'package:yr_file_explorer/features/apps/presentation/apps_page.dart';
import 'package:yr_file_explorer/features/archives/presentation/archive_page.dart';
import 'package:yr_file_explorer/features/files/presentation/file_browser_page.dart';
import 'package:yr_file_explorer/features/network/presentation/bluetooth_page.dart';
import 'package:yr_file_explorer/features/network/presentation/net_manager_page.dart';
import 'package:yr_file_explorer/features/network/presentation/network_page.dart';
import 'package:yr_file_explorer/features/network/presentation/web_page.dart';
import 'package:yr_file_explorer/features/network/presentation/download_page.dart';
import 'package:yr_file_explorer/features/network/presentation/remote_browser_page.dart';
import 'package:yr_file_explorer/features/recycle_bin/presentation/recycle_bin_page.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

/// Central page dispatch; stable window IDs keep each page's state on tab changes.
class WorkspaceWindow extends StatelessWidget {
  final ExplorerWindow window;
  final AppSettings settings;
  final FileClipboard clipboard;
  const WorkspaceWindow({
    super.key,
    required this.window,
    required this.settings,
    required this.clipboard,
  });

  @override
  Widget build(BuildContext context) => switch (window.page) {
    'analysis_results' => AnalysisResultsPage(
      settings: settings,
      clipboard: clipboard,
      windowId: window.id,
      path: window.path,
      kind: window.category ?? 'large',
      title: window.title ?? 'Analysis results',
      payload: window.payload,
    ),
    'web' => WebPage(
      settings: settings,
      windowId: window.id,
      address: window.url ?? 'https://example.com',
    ),
    'downloads' => DownloadPage(
      settings: settings,
      windowId: window.id,
      initialUrl: window.url,
    ),
    'storage_analysis' => AnalysisPage(
      settings: settings,
      windowId: window.id,
      path: window.path,
    ),
    'bluetooth' => BluetoothPage(
      settings: settings,
      windowId: window.id,
      clipboard: clipboard,
    ),
    'netmanager' => NetManagerPage(settings: settings, windowId: window.id),
    'network' || 'lan' || 'ftp' || 'webdav' => NetworkPage(
      settings: settings,
      windowId: window.id,
      clipboard: clipboard,
      section: switch (window.page) {
        'lan' => 'LAN',
        'ftp' => 'FTP',
        'webdav' => 'WebDAV',
        _ => 'Network',
      },
    ),
    'analysis' => SdCardAnalyst(
      settings: settings,
      clipboard: clipboard,
      windowId: window.id,
      path: window.path,
    ),
    'archive' => ArchivePage(
      settings: settings,
      clipboard: clipboard,
      windowId: window.id,
      path: window.path,
    ),
    'apps' => AppsPage(settings: settings, windowId: window.id),
    'trash' => TrashPage(settings: settings, windowId: window.id),
    _ =>
      window.profile == null
          ? FileBrowser(
              settings: settings,
              clipboard: clipboard,
              windowId: window.id,
              path: window.path,
              category: window.category,
              title: window.title,
              recent: window.recent,
              initialSearch: window.search,
              split: window.split,
            )
          : RemoteBrowser(
              settings: settings,
              clipboard: clipboard,
              windowId: window.id,
              profile: window.profile!,
            ),
  };
}
