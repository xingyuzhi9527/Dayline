import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class ReviewOrb extends StatefulWidget {
  const ReviewOrb({
    required this.recordCount,
    required this.hasUnfinishedTodos,
    required this.isEvening,
    required this.isReviewed,
    required this.onTap,
    super.key,
  });

  final int recordCount;
  final bool hasUnfinishedTodos;
  final bool isEvening;
  final bool isReviewed;
  final VoidCallback onTap;

  @override
  State<ReviewOrb> createState() => _ReviewOrbState();
}

class _ReviewOrbState extends State<ReviewOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowChild = _GlowCircle(
      glowColor: _glowColor,
      isActive: _isActive,
    );
    final orbChild = _MainOrb(
      orbGradient: _orbGradient,
      isEveningActive: _isEveningActive,
      recordCount: widget.recordCount,
      isReviewed: widget.isReviewed,
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _breathController,
                child: glowChild,
                builder: (context, child) {
                  final breath = _breathController.value;
                  final scale = 1.0 + breath * (_isActive ? 0.03 : 0.015);
                  return Transform.scale(
                    scale: scale + 0.04,
                    child: child,
                  );
                },
              ),
              AnimatedBuilder(
                animation: _breathController,
                child: orbChild,
                builder: (context, child) {
                  final breath = _breathController.value;
                  final scale = 1.0 + breath * (_isActive ? 0.03 : 0.015);
                  return Transform.scale(
                    scale: scale,
                    child: child,
                  );
                },
              ),
              if (widget.hasUnfinishedTodos && !widget.isReviewed)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.todo.withAlpha(200),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isEveningActive => widget.isEvening && !widget.isReviewed;
  bool get _isActive => _isEveningActive || widget.recordCount > 0;

  Color get _glowColor {
    if (widget.isReviewed) return AppColors.tracker;
    return AppColors.primary;
  }

  Gradient get _orbGradient {
    if (widget.isReviewed) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6B9E7A), Color(0xFF4F7D45)],
      );
    }
    if (_isEveningActive) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5A9FA3), Color(0xFF2F6F73)],
      );
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8AB4B7), Color(0xFF5A8A8E)],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.glowColor, required this.isActive});

  final Color glowColor;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final opacity = (isActive ? 0.05 : 0.03) * 255;
    return Container(
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: glowColor.withAlpha(opacity.round()),
      ),
    );
  }
}

class _MainOrb extends StatelessWidget {
  const _MainOrb({
    required this.orbGradient,
    required this.isEveningActive,
    required this.recordCount,
    required this.isReviewed,
  });

  final Gradient orbGradient;
  final bool isEveningActive;
  final int recordCount;
  final bool isReviewed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      height: 170,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: orbGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(isEveningActive ? 50 : 28),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: _OrbContent(recordCount: recordCount, isReviewed: isReviewed),
    );
  }
}

class _OrbContent extends StatelessWidget {
  const _OrbContent({required this.recordCount, required this.isReviewed});

  final int recordCount;
  final bool isReviewed;

  @override
  Widget build(BuildContext context) {
    if (recordCount == 0) {
      return const Align(
        alignment: Alignment(0, 0.12),
        child: Icon(Icons.auto_awesome_rounded, size: 48, color: Colors.white70),
      );
    }

    final fullness = (recordCount / 20).clamp(0.15, 1.0);
    return Align(
      alignment: const Alignment(0, 0.12),
      child: isReviewed
          ? const Icon(Icons.check_circle_rounded, size: 36, color: Colors.white)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 36, color: Colors.white),
                const SizedBox(height: 8),
                Container(
                  width: 64 * fullness,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(140),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
    );
  }
}
