import 'package:flutter/foundation.dart';

class PerfTrace {
  const PerfTrace._();

  static Future<T> measure<T>(String label, Future<T> Function() action) async {
    if (!kDebugMode) return action();
    final span = start(label);
    try {
      return await action();
    } finally {
      span.finish();
    }
  }

  static PerfTraceSpan start(String label) {
    if (!kDebugMode) return const PerfTraceSpan._disabled();
    return PerfTraceSpan._(label, Stopwatch()..start());
  }
}

class PerfTraceSpan {
  const PerfTraceSpan._disabled() : _label = '', _stopwatch = null;

  PerfTraceSpan._(this._label, this._stopwatch);

  final String _label;
  final Stopwatch? _stopwatch;

  void finish() {
    final stopwatch = _stopwatch;
    if (stopwatch == null) return;
    stopwatch.stop();
    debugPrint('[perf] $_label ${stopwatch.elapsedMilliseconds}ms');
  }
}
