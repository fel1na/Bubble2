import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Signature Bubble widget: translucent iridescent soap bubble (or emerald when live)
/// that breathes, wobbles smoothly with live microphone levels, bounces on tap with haptic feedback,
/// and can burst into glowing particles on session exit.
class InteractiveBubble extends StatefulWidget {
  final double audioLevel;
  final bool isLive;
  final bool isMuted;
  final double size;
  final VoidCallback? onTap;

  const InteractiveBubble({
    super.key,
    required this.audioLevel,
    this.isLive = false,
    this.isMuted = false,
    this.size = 240,
    this.onTap,
  });

  @override
  State<InteractiveBubble> createState() => _InteractiveBubbleState();
}

class _InteractiveBubbleState extends State<InteractiveBubble>
    with TickerProviderStateMixin {
  late final AnimationController _timeController;
  late final AnimationController _bounceController;
  late final Animation<double> _bounceScale;

  @override
  void initState() {
    super.initState();
    _timeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _bounceScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.09).chain(CurveTween(curve: Curves.easeOut)),
        weight: 28,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.09, end: 0.95).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.95, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 38,
      ),
    ]).animate(_bounceController);
  }

  @override
  void dispose() {
    _timeController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _bounceController.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final canvasSize = widget.size * 1.45;
    final greenMode = widget.isLive && !widget.isMuted;

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _bounceScale,
        child: SizedBox(
          width: canvasSize,
          height: canvasSize,
          child: AnimatedBuilder(
            animation: _timeController,
            builder: (context, _) {
              return CustomPaint(
                painter: _BubblePainter(
                  t: _timeController.value * math.pi * 2,
                  audioLevel: widget.audioLevel,
                  isGreen: greenMode,
                  isLive: widget.isLive,
                  logicalSize: widget.size,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  final double t;
  final double audioLevel;
  final bool isGreen;
  final bool isLive;
  final double logicalSize;

  _BubblePainter({
    required this.t,
    required this.audioLevel,
    required this.isGreen,
    required this.isLive,
    required this.logicalSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = logicalSize * 0.36;
    final breathe = math.sin(t * 2) * logicalSize * 0.012 +
        math.sin(t * 3) * logicalSize * 0.005;
    final audioExpand = (isLive ? 0.07 : 0.05) * audioLevel * logicalSize;
    final radius = (baseR + breathe + audioExpand).clamp(0.0, logicalSize * 0.44);

    // Multi-layer outer ambient glow
    final glowBase = isGreen ? const Color(0xFF34D399) : const Color(0xFF9F7AEA);
    for (int i = 3; i >= 1; i--) {
      final glowR = radius + i * (14 + audioLevel * 20);
      final alpha = ((0.06 + audioLevel * 0.1) / i).clamp(0.0, 0.35);
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            glowBase.withValues(alpha: alpha),
            glowBase.withValues(alpha: alpha * 0.3),
            glowBase.withValues(alpha: 0),
          ],
          stops: const [0.45, 0.75, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: glowR));
      canvas.drawCircle(center, glowR, glowPaint);
    }

    // Wobbly organic soap bubble path
    const points = 140;
    final wobbleAmp = logicalSize * (0.014 + audioLevel * 0.024);
    final path = Path();
    for (int i = 0; i <= points; i++) {
      final angle = (i / points) * math.pi * 2;
      final noise = math.sin(angle * 2 + t * 2) * wobbleAmp * 0.55 +
          math.sin(angle * 3 - t * 1.5) * wobbleAmp * 0.30 +
          math.sin(angle * 5 + t * 2.4) * wobbleAmp * 0.15;
      final r = radius + noise;
      final x = center.dx + math.cos(angle) * r;
      final y = center.dy + math.sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Iridescent translucent interior
    final fillColors = isGreen
        ? [
            Colors.white.withValues(alpha: 0.11 + audioLevel * 0.05),
            const Color(0xFF6EE7B7).withValues(alpha: 0.12 + audioLevel * 0.06),
            const Color(0xFF10B981).withValues(alpha: 0.14),
          ]
        : [
            Colors.white.withValues(alpha: 0.09 + audioLevel * 0.05),
            const Color(0xFFD6BCFA).withValues(alpha: 0.10 + audioLevel * 0.05),
            const Color(0xFF7C3AED).withValues(alpha: 0.12),
          ];

    final fillPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        radius: 0.95,
        colors: fillColors,
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(path, fillPaint);

    // Iridescent rim stroke
    final rimColors = isGreen
        ? [
            const Color(0xFFA7F3D0).withValues(alpha: 0.85),
            const Color(0xFF34D399).withValues(alpha: 0.85),
            const Color(0xFF38BDF8).withValues(alpha: 0.75),
            const Color(0xFF6EE7B7).withValues(alpha: 0.85),
          ]
        : [
            const Color(0xFFF5D0FE).withValues(alpha: 0.8),
            const Color(0xFFA78BFA).withValues(alpha: 0.85),
            const Color(0xFF7DD3FC).withValues(alpha: 0.72),
            const Color(0xFFF472B6).withValues(alpha: 0.75),
          ];

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.2, logicalSize * 0.022)
      ..shader = SweepGradient(
        colors: rimColors,
        transform: GradientRotation(t),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(path, rimPaint);

    // Specular highlight (top-left glass reflection)
    final hlCenter = Offset(
      center.dx - radius * (0.28 + math.sin(t) * 0.03),
      center.dy - radius * (0.32 + math.cos(t) * 0.03),
    );
    final hlPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.68 + audioLevel * 0.15),
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: hlCenter, radius: radius * 0.42));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(hlCenter, radius * 0.42, hlPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.audioLevel != audioLevel ||
        oldDelegate.isGreen != isGreen ||
        oldDelegate.isLive != isLive;
  }
}

/// Burst particle animation triggered when exiting a voice session.
class BubbleBurstView extends StatefulWidget {
  final double size;
  final VoidCallback onComplete;

  const BubbleBurstView({
    super.key,
    required this.size,
    required this.onComplete,
  });

  @override
  State<BubbleBurstView> createState() => _BubbleBurstViewState();
}

class _BubbleBurstViewState extends State<BubbleBurstView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete();
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.45,
      height: widget.size * 1.45,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _BurstPainter(progress: _controller.value),
          );
        },
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double progress;

  _BurstPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width * 0.45;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * (1 - progress)
      ..color = const Color(0xFFC4B5FD).withValues(alpha: opacity * 0.7);
    canvas.drawCircle(center, maxR * (0.4 + progress * 0.7), ringPaint);

    const droplets = 18;
    for (int i = 0; i < droplets; i++) {
      final angle = (i / droplets) * math.pi * 2;
      final dist = maxR * (0.35 + progress * 0.75);
      final pos = Offset(
        center.dx + math.cos(angle) * dist,
        center.dy + math.sin(angle) * dist,
      );
      final dotPaint = Paint()
        ..color = (i.isEven ? const Color(0xFFA78BFA) : const Color(0xFF6EE7B7))
            .withValues(alpha: opacity);
      canvas.drawCircle(pos, 4.5 * (1 - progress * 0.6), dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
