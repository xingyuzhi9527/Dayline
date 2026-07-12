import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/theme/app_theme.dart';
import 'package:liflow_app/features/flash_record/widgets/voice_button.dart';

void main() {
  testWidgets('idle voice button exposes tap and hold instructions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var startCount = 0;

    await tester.pumpWidget(_host(onStart: () => startCount += 1));

    expect(
      tester.getSemantics(_voiceSemantics),
      matchesSemantics(
        label: '语音记录',
        value: '待录音',
        hint: '点按开始录音，或按住说话、松开结束',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(_voiceSemantics);
    expect(startCount, 1);
    semantics.dispose();
  });

  testWidgets('listening voice button announces state and can stop', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var stopCount = 0;

    await tester.pumpWidget(
      _host(phase: 'listening', onStop: () => stopCount += 1),
    );

    expect(
      tester.getSemantics(_voiceSemantics),
      matchesSemantics(
        label: '语音记录',
        value: '正在录音',
        hint: '点按结束录音',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isLiveRegion: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(_voiceSemantics);
    expect(stopCount, 1);
    semantics.dispose();
  });

  testWidgets('saving and unavailable voice states disable tap semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var startCount = 0;

    await tester.pumpWidget(
      _host(phase: 'saving', onStart: () => startCount += 1),
    );
    expect(
      tester.getSemantics(_voiceSemantics),
      matchesSemantics(
        label: '语音记录',
        value: '正在保存',
        hint: '录音保存期间暂不可操作',
        isButton: true,
        hasEnabledState: true,
        isLiveRegion: true,
      ),
    );

    await tester.pumpWidget(
      _host(voiceAvailable: false, onStart: () => startCount += 1),
    );
    expect(
      tester.getSemantics(_voiceSemantics),
      matchesSemantics(
        label: '语音记录',
        value: '不可用',
        hint: '语音功能当前不可用',
        isButton: true,
        hasEnabledState: true,
      ),
    );

    await tester.tap(_voiceSemantics);
    expect(startCount, 0);
    semantics.dispose();
  });

  testWidgets('voice button colors follow the active dark color scheme', (
    tester,
  ) async {
    final theme = AppTheme.dark();

    await tester.pumpWidget(_host(theme: theme));

    final icon = tester.widget<Icon>(find.byIcon(Icons.mic));
    expect(icon.color, theme.colorScheme.primary);
  });
}

Finder get _voiceSemantics => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == '语音记录',
);

Widget _host({
  ThemeData? theme,
  String phase = 'idle',
  bool voiceAvailable = true,
  VoidCallback? onStart,
  VoidCallback? onStop,
}) {
  return MaterialApp(
    theme: theme ?? AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: VoiceButton(
          phase: phase,
          voiceAvailable: voiceAvailable,
          onStart: onStart ?? () {},
          onStop: onStop ?? () {},
        ),
      ),
    ),
  );
}
