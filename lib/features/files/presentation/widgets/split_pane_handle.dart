import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

/// Centered horizontal dots; drag vertically to resize or tap to expand.
class SplitPaneHandle extends StatefulWidget {
  static const height = 40.0;
  final bool expanded;
  final VoidCallback onToggle, onIncrease, onDecrease;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  const SplitPaneHandle({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDragStart,
    required this.onDragUpdate,
  });

  @override
  State<SplitPaneHandle> createState() => _SplitPaneHandleState();
}

class _SplitPaneHandleState extends State<SplitPaneHandle> {
  bool pressed = false, dragging = false;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: SplitPaneHandle.height,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (pressed || dragging)
          const Positioned(
            left: 0,
            right: 0,
            top: SplitPaneHandle.height / 2 - 1,
            child: IgnorePointer(
              child: ColoredBox(color: primaryBlue, child: SizedBox(height: 2)),
            ),
          ),
        Center(
          child: Semantics(
            button: true,
            label: widget.expanded
                ? 'Restore split height'
                : 'Expand lower pane',
            hint: 'Drag up or down to resize',
            onIncrease: widget.onIncrease,
            onDecrease: widget.onDecrease,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (details) {
                  setState(() => dragging = true);
                  widget.onDragStart(details);
                },
                onVerticalDragUpdate: widget.onDragUpdate,
                onVerticalDragEnd: (_) => setState(() => dragging = false),
                onVerticalDragCancel: () => setState(() => dragging = false),
                child: SizedBox(
                  width: 56,
                  height: SplitPaneHandle.height,
                  child: Center(
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 2,
                      animationDuration: Duration.zero,
                      shape: StadiumBorder(
                        side: BorderSide(
                          width: 2,
                          color: pressed || dragging
                              ? primaryBlue
                              : Colors.transparent,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: widget.onToggle,
                        onHighlightChanged: (value) =>
                            setState(() => pressed = value),
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        splashFactory: NoSplash.splashFactory,
                        child: SizedBox(
                          width: 52,
                          height: 24,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < 4; i++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: primaryBlue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
