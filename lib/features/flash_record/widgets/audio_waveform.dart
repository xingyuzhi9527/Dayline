import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class AudioWaveform extends StatelessWidget {
  const AudioWaveform({
    required this.level,
    required this.active,
    super.key,
  });

  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 36,
      child: CustomPaint(
        painter: _AudioWaveformPainter(
          level: level.clamp(0.0, 1.0).toDouble(),
          active: active,
        ),
      ),
    );
  }
}

class _AudioWaveformPainter extends CustomPainter {
  const _AudioWaveformPainter({
    required this.level,
    required this.active,
  });

  final double level;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (active ? AppColors.primary : AppColors.muted).withAlpha(
        active ? 190 : 90,
      )
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const bars = 21;
    final gap = size.width / (bars - 1);
    final centerY = size.height / 2;
    final base = active ? 0.16 : 0.08;
    final normalized = active ? math.max(level, 0.08) : 0.04;

    for (var i = 0; i < bars; i++) {
      final distance = (i - (bars - 1) / 2).abs() / ((bars - 1) / 2);
      final shape = math.cos(distance * math.pi / 2);
      final height = size.height * (base + normalized * 0.72 * shape);
      final x = i * gap;
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.active != active;
  }
}
