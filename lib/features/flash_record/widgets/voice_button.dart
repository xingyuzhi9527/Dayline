import 'package:flutter/material.dart';

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

  void _handleTap() {
    if (_longPressActive || widget.phase == 'saving') return;

    if (widget.phase == 'listening') {
      widget.onStop();
    } else if (widget.voiceAvailable) {
      widget.onStart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isListening = widget.phase == 'listening';
    final isSaving = widget.phase == 'saving';
    final showUnavailable =
        !widget.voiceAvailable && !isListening && widget.phase != 'saving';
    final canTap = isListening || (!isSaving && widget.voiceAvailable);
    final semanticsValue = switch (widget.phase) {
      'listening' => '正在录音',
      'saving' => '正在保存',
      _ when showUnavailable => '不可用',
      _ => '待录音',
    };
    final semanticsHint = switch (widget.phase) {
      'listening' => '点按结束录音',
      'saving' => '录音保存期间暂不可操作',
      _ when showUnavailable => '语音功能当前不可用',
      _ => '点按开始录音，或按住说话、松开结束',
    };

    return SizedBox.square(
      dimension: 292,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulseOpacity = isListening
              ? 0.15 + _pulseController.value * 0.1
              : 0.0;

          return Stack(
            alignment: Alignment.center,
            children: [
              if (isListening)
                Transform.scale(
                  scale: 1.0 + _pulseController.value * 0.3,
                  child: Container(
                    width: 188,
                    height: 188,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary.withAlpha(
                        (pulseOpacity * 255).round(),
                      ),
                    ),
                  ),
                ),
              SizedBox.square(
                dimension: 188,
                child: Semantics(
                  container: true,
                  button: true,
                  enabled: canTap,
                  liveRegion: isListening || isSaving,
                  label: '语音记录',
                  value: semanticsValue,
                  hint: semanticsHint,
                  onTap: canTap ? _handleTap : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: canTap ? _handleTap : null,
                    onLongPressStart:
                        isListening || isSaving || !widget.voiceAvailable
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
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 200),
                      scale: isListening ? 1.15 : (_isPressed ? 0.95 : 1.0),
                      child: AnimatedContainer(
                        key: const ValueKey('voice-button-surface'),
                        duration: const Duration(milliseconds: 300),
                        width: 166,
                        height: 166,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isListening
                              ? colorScheme.primary
                              : showUnavailable
                              ? colorScheme.onSurface.withAlpha(30)
                              : colorScheme.primary.withAlpha(25),
                          boxShadow: isListening
                              ? [
                                  BoxShadow(
                                    color: colorScheme.primary.withAlpha(60),
                                    blurRadius: 32,
                                    spreadRadius: 4,
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color:
                                        (showUnavailable
                                                ? colorScheme.onSurfaceVariant
                                                : colorScheme.primary)
                                            .withAlpha(25),
                                    blurRadius: 16,
                                    spreadRadius: 0,
                                  ),
                                ],
                        ),
                        child: Icon(
                          showUnavailable ? Icons.mic_off : Icons.mic,
                          size: 72,
                          color: isListening
                              ? colorScheme.onPrimary
                              : showUnavailable
                              ? colorScheme.onSurfaceVariant.withAlpha(120)
                              : colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
