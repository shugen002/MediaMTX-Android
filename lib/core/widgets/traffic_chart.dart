import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../data/models/media_snapshot.dart';

class TrafficChart extends StatelessWidget {
  const TrafficChart({super.key, required this.samples, this.height = 122});

  final List<TrafficSample> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (samples.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '正在采集流量样本…',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.textTertiary),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrafficPainter(
          samples: samples,
          inboundColor: colors.chartIn,
          outboundColor: colors.chartOut,
          gridColor: colors.border.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter({
    required this.samples,
    required this.inboundColor,
    required this.outboundColor,
    required this.gridColor,
  });

  final List<TrafficSample> samples;
  final Color inboundColor;
  final Color outboundColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final maxValue = samples.fold<double>(
      0,
      (value, sample) =>
          math.max(value, math.max(sample.inboundRate, sample.outboundRate)),
    );
    final max = maxValue <= 0 ? 1.0 : maxValue * 1.18;
    const left = 2.0;
    const right = 2.0;
    final width = size.width - left - right;
    final height = size.height - 6;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;
    for (var i = 1; i < 4; i++) {
      final y = height * i / 4;
      final path = Path()..moveTo(left, y);
      var x = left;
      while (x < left + width) {
        path.lineTo(math.min(x + 4, left + width), y);
        x += 9;
      }
      canvas.drawPath(path, gridPaint);
    }

    List<Offset> points(double Function(TrafficSample) value) {
      return [
        for (var i = 0; i < samples.length; i++)
          Offset(
            left + width * i / (samples.length - 1),
            4 + height - (value(samples[i]) / max).clamp(0.0, 1.0) * height,
          ),
      ];
    }

    final inbound = points((sample) => sample.inboundRate);
    final outbound = points((sample) => sample.outboundRate);

    _drawSeries(canvas, size, inbound, inboundColor);
    _drawSeries(canvas, size, outbound, outboundColor);
  }

  void _drawSeries(Canvas canvas, Size size, List<Offset> points, Color color) {
    if (points.isEmpty) return;
    final path = _smoothPath(points);
    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, size.height), [
        color.withValues(alpha: 0.22),
        color.withValues(alpha: 0.0),
      ]);
    canvas.drawPath(fill, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final dot = Offset(points.last.dx, points.last.dy);
    canvas.drawCircle(dot, 4.5, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawCircle(dot, 2.2, Paint()..color = color);
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 2) {
      path.lineTo(points[1].dx, points[1].dy);
      return path;
    }
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[math.max(i - 1, 0)];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[math.min(i + 2, points.length - 1)];
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.inboundColor != inboundColor ||
        oldDelegate.outboundColor != outboundColor;
  }
}
