import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';

class WindowPanelTabs extends StatelessWidget {
  final int windows, clipboard;
  const WindowPanelTabs({
    super.key,
    required this.windows,
    required this.clipboard,
  });
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 284),
        child: SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: controller.animation!,
              builder: (context, _) {
                final progress = controller.animation!.value.clamp(0.0, 1.0);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 5,
                      bottom: 5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xff202020)
                                : const Color(0xffe7e9ec),
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(
                              color: dark
                                  ? Colors.white12
                                  : const Color(0xffd0d4d9),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Align(
                              alignment: Alignment(-1 + 2 * progress, 0),
                              child: FractionallySizedBox(
                                widthFactor: .5,
                                heightFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: dark
                                        ? const Color(0xff454545)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(15),
                                    boxShadow: dark
                                        ? null
                                        : const [
                                            BoxShadow(
                                              color: Color(0x18000000),
                                              blurRadius: 3,
                                              offset: Offset(0, 1),
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
                    Row(
                      children: [
                        for (var i = 0; i < 2; i++)
                          Expanded(
                            child: Semantics(
                              selected: controller.index == i,
                              button: true,
                              child: InkWell(
                                // The custom pill is the selection feedback. Ink
                                // on the dialog's Material leaked past its track.
                                splashFactory: NoSplash.splashFactory,
                                overlayColor: const WidgetStatePropertyAll(
                                  Colors.transparent,
                                ),
                                borderRadius: BorderRadius.circular(17),
                                onTap: () => controller.animateTo(
                                  i,
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 220),
                                  curve: Curves.easeInOutCubic,
                                ),
                                child: SizedBox(
                                  height: 44,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              i == 0
                                                  ? Icons.filter_none
                                                  : Icons
                                                        .content_paste_outlined,
                                              size: 15,
                                              color: controller.index == i
                                                  ? explorerForeground(context)
                                                  : dark
                                                  ? Colors.white60
                                                  : const Color(0xff6b7785),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              i == 0
                                                  ? 'Windows ($windows)'
                                                  : clipboard == 0
                                                  ? 'Clipboard'
                                                  : 'Clipboard ($clipboard)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: controller.index == i
                                                    ? explorerForeground(
                                                        context,
                                                      )
                                                    : dark
                                                    ? Colors.white60
                                                    : const Color(0xff6b7785),
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
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
