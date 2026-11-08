import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/files/presentation/file_browser_page.dart';
import 'package:yr_file_explorer/features/files/presentation/widgets/split_pane_handle.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

import 'segmented_tabs.dart';
import 'split_pane_scope.dart';

/// FTP/SFTP/FTPS browser above Device, with one toolbar for the focused pane.
class RemoteSplitWorkspace extends StatefulWidget {
  final Widget child;
  final AppSettings settings;
  final FileClipboard clipboard;
  final int windowId;
  const RemoteSplitWorkspace({
    super.key,
    required this.child,
    required this.settings,
    required this.clipboard,
    required this.windowId,
  });
  @override
  State<RemoteSplitWorkspace> createState() => _RemoteSplitWorkspaceState();
}

class _RemoteSplitWorkspaceState extends State<RemoteSplitWorkspace> {
  final lower = GlobalKey<FileBrowserState>();
  Widget? upperToolbar;
  bool lowerActive = false;
  double ratio = .5, startY = 0, startRatio = .5;
  void focus(bool value) {
    if (lowerActive != value) setState(() => lowerActive = value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    appBar: AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: explorerTabHeight,
      titleSpacing: 0,
      title: ReferenceTabs(
        onLocal: () => ExplorerWorkspaceSession.instance.open(
          ExplorerWorkspaceSession.instance.root,
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimum = (120 / constraints.maxHeight).clamp(.2, .5);
          final value = ratio.clamp(minimum, 1 - minimum);
          void resize(double next) =>
              setState(() => ratio = next.clamp(minimum, 1 - minimum));
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    flex: (value * 1000).round(),
                    child: Listener(
                      onPointerDown: (_) => focus(false),
                      child: ClipRect(
                        child: SplitPaneScope(
                          onToolbar: (bar) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && !identical(upperToolbar, bar)) {
                                setState(() => upperToolbar = bar);
                              }
                            });
                          },
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            removeBottom: true,
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: ((1 - value) * 1000).round(),
                    child: Listener(
                      onPointerDown: (_) => focus(true),
                      child: ClipRect(
                        child: FileBrowser(
                          key: lower,
                          settings: widget.settings,
                          clipboard: widget.clipboard,
                          path: ExplorerWorkspaceSession.instance.root,
                          embedded: true,
                          onClosePane: () => ExplorerWorkspaceSession.instance
                              .setSplit(widget.windowId, false),
                          onPaneStateChanged: () {
                            if (mounted && lowerActive) setState(() {});
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: constraints.maxHeight * value - SplitPaneHandle.height / 2,
                left: 0,
                right: 0,
                child: SplitPaneHandle(
                  expanded: value <= minimum + .001,
                  onToggle: () =>
                      resize(value <= minimum + .001 ? .5 : minimum),
                  onIncrease: () => resize(value + .05),
                  onDecrease: () => resize(value - .05),
                  onDragStart: (details) {
                    startY = details.globalPosition.dy;
                    startRatio = value;
                  },
                  onDragUpdate: (details) => resize(
                    startRatio +
                        (details.globalPosition.dy - startY) /
                            constraints.maxHeight,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    bottomNavigationBar: lowerActive
        ? lower.currentState?.bottomToolbar() ?? upperToolbar
        : upperToolbar,
  );
}
