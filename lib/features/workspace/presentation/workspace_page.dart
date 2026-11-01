import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/analysis/presentation/sd_card_analyst_page.dart';
import 'package:yr_file_explorer/features/analysis/presentation/storage_analysis_page.dart';
import 'package:yr_file_explorer/features/apps/presentation/apps_page.dart';
import 'package:yr_file_explorer/features/archives/presentation/archive_page.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/files/presentation/file_browser_page.dart';
import 'package:yr_file_explorer/features/home/presentation/home_page.dart';
import 'package:yr_file_explorer/features/network/presentation/bluetooth_page.dart';
import 'package:yr_file_explorer/features/network/presentation/net_manager_page.dart';
import 'package:yr_file_explorer/features/network/presentation/network_page.dart';
import 'package:yr_file_explorer/features/network/presentation/remote_browser_page.dart';
import 'package:yr_file_explorer/features/recycle_bin/presentation/recycle_bin_page.dart';
import 'package:yr_file_explorer/features/settings/presentation/settings_page.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/workspace_page_deck.dart';

class ExplorerWorkspace extends StatefulWidget {
  final AppSettings settings;
  const ExplorerWorkspace({super.key, required this.settings});
  @override
  State<ExplorerWorkspace> createState() => _ExplorerWorkspaceState();
}

class _ExplorerWorkspaceState extends State<ExplorerWorkspace> {
  final session = ExplorerWorkspaceSession.instance;
  final clipboard = FileClipboard();
  bool restoredDefaults = false;
  int previewEpoch = 0;
  int? previewActiveId;
  bool previewRequested = false;
  Brightness? previewBrightness;

  void queuePreview() {
    final epoch = ++previewEpoch;
    final id = session.activeId;
    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      if (mounted && epoch == previewEpoch && id == session.activeId) {
        await captureCurrent();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (previewBrightness != brightness) {
      previewBrightness = brightness;
      queuePreview();
    }
  }

  @override
  void initState() {
    super.initState();
    session.addListener(changed);
    clipboard.addListener(session.clipboardChanged);
    session.onTool = openTool;
    session.onServer = openServer;
    session.servers = widget.settings.connections;
    session.defaults = widget.settings.defaultWindows;
    session.onSaveDefaults = (values) {
      widget.settings.defaultWindows = values;
      widget.settings.save();
    };
    session.beforeSwitch = captureCurrent;
    session.clipboardItems = () => clipboard.paths;
    session.clipboardMove = () => clipboard.move;
    session.clearClipboard = clipboard.clear;
    session.onPermissionGranted = restoreDefaults;
  }

  void restoreDefaults() {
    if (restoredDefaults) return;
    restoredDefaults = true;
    for (final entry in session.defaults) {
      if (entry['page'] == 'analysis' && entry['path'] is String) {
        session.open(entry['path'], page: 'analysis', title: 'SD Card Analyst');
        continue;
      }
      if (entry['page'] != null &&
          entry['page'] != 'files' &&
          entry['page'] != 'archive') {
        session.openPage(entry['page']);
        continue;
      }
      if (entry['path'] is String) {
        session.open(
          entry['path'],
          page: entry['page'] ?? 'files',
          category: entry['category'],
          title: entry['title'],
          recent: entry['recent'] == true,
        );
      }
    }
  }

  void changed() {
    if (!mounted) return;
    setState(() {});
    if (!previewRequested || previewActiveId != session.activeId) {
      previewRequested = true;
      previewActiveId = session.activeId;
      queuePreview();
    }
  }

  Future<void> captureCurrent() async {
    if (!mounted) return;
    final id = session.activeId;
    final key = id == null
        ? session.homePreviewKey
        : session.windows.where((w) => w.id == id).firstOrNull?.previewKey;
    final boundary = key?.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    if (boundary.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || id != session.activeId || boundary.debugNeedsPaint) {
        return;
      }
    }
    try {
      final image = await boundary.toImage(pixelRatio: .6);
      if (!mounted || id != session.activeId) {
        image.dispose();
        return;
      }
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes != null && mounted && id == session.activeId) {
        session.setPreview(id, bytes.buffer.asUint8List());
      }
    } catch (_) {
      /* A loading tab may not have a painted frame yet. */
    }
  }

  void openServer(Json profile) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NetworkPage(
        settings: widget.settings,
        clipboard: clipboard,
        initialProfile: profile,
      ),
    ),
  );
  void openTool(String page) {
    if (page == 'analysis') {
      final current = session.windows
          .where((w) => w.id == session.activeId)
          .firstOrNull;
      final path = current == null || current.profile != null
          ? session.root
          : current.page == 'archive'
          ? parentPath(current.path)
          : current.path;
      session.open(path, page: 'analysis', title: 'SD Card Analyst');
      return;
    }
    if ([
      'apps',
      'network',
      'trash',
      'analysis',
      'lan',
      'ftp',
      'webdav',
      'bluetooth',
      'netmanager',
    ].contains(page)) {
      session.openPage(page);
      return;
    }
    final path =
        session.windows
            .where((w) => w.id == session.activeId)
            .firstOrNull
            ?.path ??
        session.root;
    final Widget screen = switch (page) {
      'apps' => AppsPage(settings: widget.settings),
      'trash' => TrashPage(settings: widget.settings),
      'network' || 'ftp' || 'sftp' => NetworkPage(
        settings: widget.settings,
        clipboard: clipboard,
        initialProtocol: page == 'ftp'
            ? 'FTP'
            : page == 'sftp'
            ? 'SFTP'
            : null,
      ),
      'analysis' => AnalysisPage(
        path: path,
        onBrowse: (path) => session.open(path),
      ),
      _ => SettingsPage(settings: widget.settings),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  void dispose() {
    session.removeListener(changed);
    session.onTool = null;
    session.onServer = null;
    session.beforeSwitch = null;
    session.onPermissionGranted = null;
    session.onSaveDefaults = null;
    clipboard.removeListener(session.clipboardChanged);
    clipboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspacePageDeck(
    activeId: session.activeId ?? 0,
    pageIds: [0, for (final window in session.windows) window.id],
    children: [
      RepaintBoundary(
        key: session.homePreviewKey,
        child: ExplorerHome(settings: widget.settings, clipboard: clipboard),
      ),
      for (final window in session.windows)
        TickerMode(
          key: ValueKey(window.id),
          enabled: session.activeId == window.id,
          child: RepaintBoundary(
            key: window.previewKey,
            child: window.page == 'bluetooth'
                ? BluetoothPage(
                    windowId: window.id,
                    settings: widget.settings,
                    clipboard: clipboard,
                  )
                : window.page == 'netmanager'
                ? NetManagerPage(windowId: window.id, settings: widget.settings)
                : ['lan', 'ftp', 'webdav'].contains(window.page)
                ? NetworkPage(
                    windowId: window.id,
                    settings: widget.settings,
                    clipboard: clipboard,
                    section: window.page == 'lan'
                        ? 'LAN'
                        : window.page == 'ftp'
                        ? 'FTP'
                        : 'WebDAV',
                  )
                : window.page == 'analysis'
                ? SdCardAnalyst(
                    windowId: window.id,
                    path: window.path,
                    settings: widget.settings,
                  )
                : window.page == 'archive'
                ? ArchivePage(
                    windowId: window.id,
                    path: window.path,
                    settings: widget.settings,
                    clipboard: clipboard,
                  )
                : window.page == 'apps'
                ? AppsPage(windowId: window.id, settings: widget.settings)
                : window.page == 'network'
                ? NetworkPage(
                    windowId: window.id,
                    settings: widget.settings,
                    clipboard: clipboard,
                  )
                : window.page == 'trash'
                ? TrashPage(windowId: window.id, settings: widget.settings)
                : window.profile == null
                ? FileBrowser(
                    windowId: window.id,
                    path: window.path,
                    settings: widget.settings,
                    clipboard: clipboard,
                    category: window.category,
                    title: window.title,
                    recent: window.recent,
                    initialSearch: window.search,
                  )
                : RemoteBrowser(
                    windowId: window.id,
                    profile: window.profile!,
                    settings: widget.settings,
                    clipboard: clipboard,
                  ),
          ),
        ),
    ],
  );
}
