import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class VoiceButton extends StatefulWidget {
  const VoiceButton({
    required this.phase,
    required this.onStart,
    required this.onStop,
    this.voiceAvailable = true,
    super.key,
  });

  final String phase;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final bool voiceAvailable;

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _isPressed = false;
  bool _longPressActive = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startPulse() {
    _pulseController.repeat(reverse: true);
  }

  void _stopPulse() {
    _pulseController.stop();
    _pulseController.value = 0;
  }

  @override
  void didUpdateWidget(VoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == 'listening' && oldWidget.phase != 'listening') {
      _startPulse();
    } else if (widget.phase != 'listening' && oldWidget.phase == 'listening') {
      _stopPulse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isListening = widget.phase == 'listening';
    final isSaving = widget.phase == 'saving';
    final showUnavailable = !widget.voiceAvailable &&
        !isListening &&
        widget.phase != 'saving';

    return SizedBox.square(
      dimension: 220,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isSaving
            ? null
            : () {
                if (_longPressActive) return;
                if (isListening) {
                  widget.onStop();
                } else if (widget.voiceAvailable) {
                  widget.onStart();
                }
              },
        onLongPressStart: isListening || isSaving || !widget.voiceAvailable
            ? null
            : (_) {
                setState(() {
                  _isPressed = true;
                  _longPressActive = true;
                });
                widget.onStart();
              },
        onLongPressEnd: (_) {
          if (_longPressActive) {
            setState(() {
              _isPressed = false;
              _longPressActive = false;
            });
            widget.onStop();
          }
        },
        onLongPressCancel: () {
          if (!_longPressActive) return;
          setState(() {
            _isPressed = false;
            _longPressActive = false;
          });
          widget.onStop();
        },
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final pulseOpacity = isListening
                ? 0.15 + _pulseController.value * 0.1
                : 0.0;

            return Stack(
              alignment: Alignment.center,
              children: [
                // Pulse ring
                if (isListening)
                  Transform.scale(
                    scale: 1.0 + _pulseController.value * 0.3,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withAlpha(
                          (pulseOpacity * 255).round(),
                        ),
                      ),
                    ),
                  ),
                // Main button
                AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: isListening ? 1.15 : (_isPressed ? 0.95 : 1.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isListening
                          ? AppColors.primary
                          : showUnavailable
                          ? AppColors.muted.withAlpha(30)
                          : AppColors.primary.withAlpha(25),
                      boxShadow: isListening
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withAlpha(60),
                                blurRadius: 32,
                                spreadRadius: 4,
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: (showUnavailable
                                        ? AppColors.muted
                                        : AppColors.primary)
                                    .withAlpha(25),
                                blurRadius: 16,
                                spreadRadius: 0,
                              ),
                            ],
                    ),
                    child: Icon(
                      showUnavailable ? Icons.mic_off : Icons.mic,
                      size: 52,
                      color: isListening
                          ? Colors.white
                          : showUnavailable
                          ? AppColors.muted.withAlpha(120)
                          : AppColors.primary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
