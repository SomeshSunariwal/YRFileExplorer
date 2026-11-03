import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/file_categories.dart';

class WindowPreviewCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Uint8List? preview;
  final bool selected, isDefault, locked;
  final VoidCallback onSelect, onDefault;
  final VoidCallback? onClose;
  const WindowPreviewCard({
    super.key,
    required this.label,
    required this.icon,
    required this.preview,
    required this.selected,
    required this.isDefault,
    required this.locked,
    required this.onSelect,
    required this.onDefault,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outline = selected ? primaryBlue : Theme.of(context).dividerColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xff393939) : const Color(0xffe5eaf0);
    final buttonSurface = colors.surface.withValues(alpha: .96);
    final bandColor = Color.lerp(surface, primaryBlue, selected ? .20 : .12)!;
    return Material(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preview != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: Image.memory(
                    preview!,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -.6),
                    excludeFromSemantics: true,
                  ),
                ),
              )
            else
              Center(child: Icon(icon, size: 36, color: primaryBlue)),
            // Overlay the fade on the screenshot, occupying exactly its lower sixth.
            Column(
              children: [
                const Spacer(flex: 5),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [bandColor, bandColor.withValues(alpha: 0)],
                        stops: const [0, 1],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(
                                alpha: dark ? .25 : .08,
                              ),
                              offset: const Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 2,
              left: 2,
              child: _PreviewControl(
                tooltip: isDefault
                    ? 'Default startup tab'
                    : 'Set as default startup tab',
                onPressed: onDefault,
                icon: isDefault ? Icons.home_rounded : Icons.home_outlined,
                foreground: isDefault ? primaryBlue : colors.onSurfaceVariant,
                background: isDefault
                    ? Color.alphaBlend(
                        primaryBlue.withValues(alpha: .10),
                        buttonSurface,
                      )
                    : buttonSurface,
              ),
            ),
            if (onClose != null)
              Positioned(
                top: 2,
                right: 2,
                child: _PreviewControl(
                  tooltip: locked ? 'Window locked' : 'Close window',
                  onPressed: locked ? null : onClose,
                  icon: locked ? Icons.lock_outline : Icons.close_rounded,
                  foreground: dark
                      ? const Color(0xffef5350)
                      : const Color(0xffd32f2f),
                  background: buttonSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewControl extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color foreground, background;
  final VoidCallback? onPressed;
  const _PreviewControl({
    required this.tooltip,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 44,
    child: Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
          ),
        ),
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(44),
            padding: EdgeInsets.zero,
            foregroundColor: foreground,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          icon: Icon(icon, size: 14),
        ),
      ],
    ),
  );
}
