import 'package:yr_file_explorer/shared/widgets/explorer_progress_bar.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';

class DownloadPage extends StatefulWidget {
  final AppSettings settings;
  final int? windowId;
  final String? initialUrl;
  const DownloadPage({
    super.key,
    required this.settings,
    this.windowId,
    this.initialUrl,
  });
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage>
    with WidgetsBindingObserver {
  List<Json> jobs = [];
  bool loading = true, busy = false, polling = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (widget.windowId == null ||
          ExplorerWorkspaceSession.instance.activeId == widget.windowId) {
        load();
      }
    });
    if (widget.initialUrl?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) newDownload(widget.initialUrl);
      });
    }
  }

  @override
  void didUpdateWidget(covariant DownloadPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUrl != oldWidget.initialUrl &&
        widget.initialUrl?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) newDownload(widget.initialUrl);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    if (polling) return;
    polling = true;
    try {
      final rows = await Native.rows('downloads');
      if (mounted) {
        setState(() {
          jobs = rows;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    } finally {
      polling = false;
    }
  }

  Future<void> newDownload([String? initial]) async {
    final args = await showDialog<Json>(
      context: context,
      builder: (_) => _DownloadForm(
        initial: initial ?? '',
        folder: '${ExplorerWorkspaceSession.instance.root}/Download',
      ),
    );
    if (args == null || !mounted) return;
    setState(() => busy = true);
    try {
      await Native.call('download', args);
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(Json job, String method) async {
    if (method == 'cancelDownload' &&
        !await confirm(
          context,
          'Cancel download?',
          'The partial download will be removed.',
          action: 'Cancel download',
        )) {
      return;
    }
    if (!mounted) return;
    try {
      await Native.call(method, {'id': job['id']});
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => ExplorerPane(
    settings: widget.settings,
    windowId: widget.windowId,
    title: const Text('Download Manager'),
    busy: busy,
    actions: [
      ExplorerAction(icon: Icons.add, label: 'New', onTap: () => newDownload()),
      ExplorerAction(icon: Icons.refresh, label: 'Refresh', onTap: load),
      ExplorerAction(
        icon: Icons.filter_none,
        label: 'Windows',
        onTap: () => showExplorerWindows(context),
      ),
    ],
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? EmptyState(
            title: 'Downloads unavailable',
            message: error!,
            action: TextButton(onPressed: load, child: const Text('Try again')),
          )
        : jobs.isEmpty
        ? EmptyState(
            icon: Icons.download_outlined,
            title: 'No downloads yet',
            message: 'Start an HTTP or HTTPS download. Android keeps it running when you leave this page.',
            action: FilledButton.icon(
              onPressed: () => newDownload(),
              icon: const Icon(Icons.add),
              label: const Text('New download'),
            ),
          )
        : ListView.builder(
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              ExplorerBottomBar.contentBottomPadding(context),
            ),
            itemCount: jobs.length,
            itemBuilder: (_, i) {
              final job = jobs[i], status = job['status'] as String;
              final bytes = (job['bytes'] as num).toDouble(),
                  total = (job['total'] as num).toDouble();
              final done = status == 'Completed', failed = status == 'Failed';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.download_outlined,
                            color: primaryBlue,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              job['name'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Download actions',
                            onSelected: (v) => action(job, v),
                            itemBuilder: (_) => [
                              if (done)
                                const PopupMenuItem(
                                  value: 'openDownload',
                                  child: Text('Open'),
                                ),
                              if (failed)
                                const PopupMenuItem(
                                  value: 'retryDownload',
                                  child: Text('Retry'),
                                ),
                              if (!done && !failed)
                                const PopupMenuItem(
                                  value: 'cancelDownload',
                                  child: Text('Cancel download'),
                                ),
                              if (done || failed)
                                const PopupMenuItem(
                                  value: 'forgetDownload',
                                  child: Text('Remove from history'),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        '$status${failed ? ' (code ${job['reason']})' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: failed
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: ExplorerProgressBar(
                            value: done
                                ? 1
                                : total > 0
                                ? (bytes / total).clamp(0, 1)
                                : failed
                                ? 0
                                : null,
                            height: 10,
                            showPercentage: total > 0 || done,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${sizeLabel(bytes)}${total > 0 ? ' / ${sizeLabel(total)}' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

class _DownloadForm extends StatefulWidget {
  final String initial, folder;
  const _DownloadForm({required this.initial, required this.folder});
  @override
  State<_DownloadForm> createState() => _DownloadFormState();
}

class _DownloadFormState extends State<_DownloadForm> {
  final form = GlobalKey<FormState>();
  late TextEditingController url, name, folder;
  @override
  void initState() {
    super.initState();
    url = TextEditingController(text: widget.initial);
    folder = TextEditingController(text: widget.folder);
    final uri = Uri.tryParse(widget.initial);
    name = TextEditingController(text: uri?.pathSegments.lastOrNull ?? '');
  }

  @override
  void dispose() {
    url.dispose();
    name.dispose();
    folder.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, {
        'url': url.text.trim(),
        'name': name.text.trim(),
        'path': folder.text.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) => ExplorerDialog(
    title: const Text(
      'New download',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'HTTP / HTTPS URL',
                ),
                validator: (value) {
                  final uri = Uri.tryParse(value?.trim() ?? '');
                  return uri != null &&
                          ['http', 'https'].contains(uri.scheme) &&
                          uri.host.isNotEmpty &&
                          uri.userInfo.isEmpty
                      ? null
                      : 'Enter a valid HTTP or HTTPS URL';
                },
                onChanged: (value) {
                  final uri = Uri.tryParse(value);
                  if (uri?.pathSegments.isNotEmpty == true &&
                      name.text.isEmpty) {
                    name.text = uri!.pathSegments.last;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'File name',
                  hintText: 'Use server name',
                ),
                validator: (v) =>
                    v != null &&
                        (v.contains('/') ||
                            v.contains('\\') ||
                            v == '.' ||
                            v == '..')
                    ? 'Enter a file name without slashes'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: folder,
                decoration: const InputDecoration(
                  labelText: 'Destination folder',
                ),
                validator: (v) =>
                    v != null &&
                        ExplorerWorkspaceSession.instance.containsStoragePath(
                          v.trim(),
                        )
                    ? null
                    : 'Choose a folder in internal storage or SD card',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: submit,
        icon: const Icon(Icons.download, size: 18),
        label: const Text('Download'),
      ),
    ],
  );
}
