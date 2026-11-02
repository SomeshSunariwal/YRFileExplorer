import 'package:flutter/material.dart';

/// Known progress fills the track; unknown progress shimmers without inventing a percentage.
class ExplorerProgressBar extends StatefulWidget {
  final double? value;
  final double height;
  final bool showPercentage;
  final String label;
  const ExplorerProgressBar({
    super.key,
    this.value,
    this.height = 10,
    this.showPercentage = false,
    this.label = 'Progress',
  });
  @override
  State<ExplorerProgressBar> createState() => _ExplorerProgressBarState();
}

class _ExplorerProgressBarState extends State<ExplorerProgressBar>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotion();
  }

  @override
  void didUpdateWidget(covariant ExplorerProgressBar old) {
    super.didUpdateWidget(old);
    syncMotion();
  }

  void syncMotion() {
    if (widget.value == null && !MediaQuery.disableAnimationsOf(context)) {
      if (!motion.isAnimating) motion.repeat();
    } else {
      motion.stop();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value?.clamp(0.0, 1.0);
    final bar = RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _GradientProgressPainter(
          value: value,
          motion: motion,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
    return Semantics(
      label: widget.label,
      value: value == null ? 'Loading' : '${(value * 100).round()}%',
      child: value == null || !widget.showPercentage
          ? SizedBox(height: widget.height, child: bar)
          : LayoutBuilder(
              builder: (context, constraints) {
                final scaler = MediaQuery.textScalerOf(context);
                final badgeWidth = scaler.scale(11) * 4 + 12;
                final badgeHeight = scaler.scale(11) * 1.3 + 8;
                return SizedBox(
                  height: widget.height + badgeHeight + 5,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: widget.height,
                        child: bar,
                      ),
                      Positioned(
                        top: 0,
                        left: (constraints.maxWidth * value - badgeWidth / 2)
                            .clamp(
                              0.0,
                              (constraints.maxWidth - badgeWidth).clamp(
                                0.0,
                                double.infinity,
                              ),
                            ),
                        child: Container(
                          width: badgeWidth,
                          height: badgeHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${(value * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _GradientProgressPainter extends CustomPainter {
  final double? value;
  final Animation<double> motion;
  final bool dark;
  _GradientProgressPainter({
    required this.value,
    required this.motion,
    required this.dark,
  }) : super(repaint: motion);
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(
      track,
      Paint()..color = dark ? const Color(0xff414141) : const Color(0xffe4edf4),
    );
    final fill = value == null ? size.width : size.width * value!;
    if (fill <= 0) return;
    final rect = Rect.fromLTWH(0, 0, fill, size.height);
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..shader = LinearGradient(
          colors: dark
              ? const [Color(0xff4299f5), Color(0xff2bd8e5)]
              : const [Color(0xff287ce7), Color(0xff16c8df)],
        ).createShader(Offset.zero & size),
    );
    if (value == null) {
      final band = Rect.fromLTWH(
        (motion.value * 2 - .5) * size.width - size.width * .4,
        0,
        size.width * .8,
        size.height,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: .5),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(band),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GradientProgressPainter old) =>
      value != old.value || dark != old.dark;
}
