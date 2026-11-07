import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/sharing/application/sharing_session.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';

Future<bool> showSharingCode(BuildContext context, Json network) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _CodeDialog(network: network),
    ) ??
    false;

class _CodeDialog extends StatefulWidget {
  final Json network;
  const _CodeDialog({required this.network});
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final text = TextEditingController();
  final focus = FocusNode();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    if (busy || text.text.length != 6) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SharingSession.instance.join(widget.network['id'], text.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is PlatformException ? e.message : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ExplorerDialog(
    title: const Text('Join network'),
    canClose: !busy,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.network['name'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter the six-digit code shown on the other device.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: Stack(
            children: [
              TextField(
                controller: text,
                focusNode: focus,
                autofocus: true,
                enabled: !busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.transparent),
                cursorColor: Colors.transparent,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  labelText: 'Six-digit authentication code',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => connect(),
              ),
              IgnorePointer(
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      for (var i = 0; i < 6; i++) ...[
                        if (i > 0) const SizedBox(width: 7),
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: text.text.length.clamp(0, 5) == i
                                    ? primaryBlue
                                    : Theme.of(context).dividerColor,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              i < text.text.length ? text.text[i] : '',
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Connecting and verifying code…'),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () async {
          if (busy) await SharingSession.instance.stop();
          if (context.mounted) Navigator.pop(context, false);
        },
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy || text.text.length != 6 ? null : connect,
        child: const Text('Connect'),
      ),
    ],
  );
}

/// Small anchored side picker. Selection queues a transfer before navigating.
Future<bool> showSharingDevices(
  BuildContext context,
  List<String> paths,
) async {
  final session = SharingSession.instance;
  await session.refresh();
  if (!context.mounted) return false;
  final device = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close device picker',
    barrierColor: Colors.black26,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(begin: const Offset(.15, .12), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    ),
    pageBuilder: (dialog, _, _) => Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          24,
          16,
          MediaQuery.paddingOf(dialog).bottom + explorerFooterHeight + 24,
        ),
        child: SizedBox(
          width: 280,
          child: Material(
            elevation: 12,
            color: Theme.of(dialog).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedBuilder(
              animation: session,
              builder: (_, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExplorerDialogHeader(title: Text('Send to')),
                  if (session.devices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'No connected devices. Join or create a network in Sharing first.',
                      ),
                    ),
                  for (final peer in session.devices)
                    ListTile(
                      leading: const Icon(
                        Icons.phone_android_outlined,
                        color: primaryBlue,
                      ),
                      title: Text(
                        peer['name'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${paths.length} selected ${paths.length == 1 ? 'item' : 'items'}',
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: primaryBlue,
                      ),
                      onTap: () => Navigator.pop(dialog, peer['id'] as String),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (device == null) return false;
  await session.send(device, paths);
  ExplorerWorkspaceSession.instance.openPage('sharing_history');
  return true;
}
