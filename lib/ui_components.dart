import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Glassmorphic translucent card container
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Gradient? gradient;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius = 20,
    this.gradient,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final container = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: gradient ?? TogetherTheme.darkCardGradient,
        border: Border.all(
          color: borderColor ?? TogetherTheme.glassBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: container,
        ),
      );
    }
    return container;
  }
}

/// Vibrant gradient primary action button
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.gradient = TogetherTheme.primaryGradient,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: onPressed == null ? null : gradient,
        color: onPressed == null ? TogetherTheme.textMuted.withOpacity(0.2) : null,
        boxShadow: onPressed == null
            ? []
            : [
                BoxShadow(
                  color: gradient.colors.first.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isLoading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: TogetherTheme.textPrimary,
                    ),
                  )
                else ...[
                  if (icon != null) ...[
                    Icon(icon, color: TogetherTheme.textPrimary, size: 22),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: TogetherTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated equalizer frequency bars
class EqualizerVisualizer extends StatefulWidget {
  final bool isPlaying;
  final Color barColor;
  final double height;
  final int barCount;

  const EqualizerVisualizer({
    super.key,
    required this.isPlaying,
    this.barColor = TogetherTheme.primaryPurpleLight,
    this.height = 28,
    this.barCount = 5,
  });

  @override
  State<EqualizerVisualizer> createState() => _EqualizerVisualizerState();
}

class _EqualizerVisualizerState extends State<EqualizerVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (index) {
            double value = math.sin((_controller.value * math.pi) + (index * 0.8)).abs();
            if (!widget.isPlaying) value = 0.2;
            final barHeight = math.max(4.0, widget.height * value);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: barHeight,
              decoration: BoxDecoration(
                color: widget.barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Spinning vinyl record disc widget for current track
class VinylDisc extends StatefulWidget {
  final bool isPlaying;
  final String title;

  const VinylDisc({
    super.key,
    required this.isPlaying,
    required this.title,
  });

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _rotationController,
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [
              Color(0xFF2D3748),
              Color(0xFF1A202C),
              Color(0xFF0F172A),
              Color(0xFF020617),
            ],
            stops: [0.0, 0.4, 0.8, 1.0],
          ),
          border: Border.all(color: TogetherTheme.glassBorder, width: 2),
          boxShadow: [
            BoxShadow(
              color: TogetherTheme.primaryPurple.withOpacity(0.25),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Vinyl grooves
            Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10, width: 1.5),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12, width: 1),
              ),
            ),
            // Center record label
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: TogetherTheme.primaryGradient,
              ),
              child: const Icon(
                Icons.music_note_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular DJ Avatar with fruit indicator
class DjAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const DjAvatar({
    super.key,
    required this.name,
    this.radius = 20,
  });

  String _getFruitEmoji(String name) {
    if (name.contains('Apple')) return '🍎';
    if (name.contains('Banana')) return '🍌';
    if (name.contains('Mango')) return '🥭';
    if (name.contains('Strawberry')) return '🍓';
    if (name.contains('Pineapple')) return '🍍';
    if (name.contains('Orange')) return '🍊';
    if (name.contains('Peach')) return '🍑';
    if (name.contains('Cherry')) return '🍒';
    if (name.contains('Blueberry')) return '🫐';
    if (name.contains('Kiwi')) return '🥝';
    if (name.contains('Papaya')) return '🪺';
    if (name.contains('Lemon')) return '🍋';
    return '🎧';
  }

  @override
  Widget build(BuildContext context) {
    final emoji = _getFruitEmoji(name);

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: TogetherTheme.primaryGradient,
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: TogetherTheme.cardSurface,
        child: Text(
          emoji,
          style: TextStyle(fontSize: radius * 1.0),
        ),
      ),
    );
  }
}

/// Pulsing radar scanning wave visual for party discovery
class RadarPulse extends StatefulWidget {
  final double size;

  const RadarPulse({super.key, this.size = 120});

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ...List.generate(3, (index) {
                final delay = index * 0.33;
                final progress = (_controller.value + delay) % 1.0;
                final opacity = (1.0 - progress).clamp(0.0, 1.0);
                final currentSize = widget.size * progress;

                return Container(
                  width: currentSize,
                  height: currentSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: TogetherTheme.primaryPurple.withOpacity(opacity * 0.5),
                      width: 2,
                    ),
                  ),
                );
              }),
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: TogetherTheme.primaryGradient,
                ),
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
