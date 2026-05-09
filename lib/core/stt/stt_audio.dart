import 'dart:math' as math;
import 'dart:typed_data';

Float32List pcm16ToFloat32(Uint8List bytes) {
  final sampleCount = bytes.lengthInBytes ~/ 2;
  final samples = Float32List(sampleCount);
  final data = ByteData.sublistView(bytes);

  for (var i = 0; i < sampleCount; i++) {
    final sample = data.getInt16(i * 2, Endian.little);
    samples[i] = (sample / 32768.0).clamp(-1.0, 1.0).toDouble();
  }

  return samples;
}

double rmsAudioLevel(Float32List samples) {
  if (samples.isEmpty) return 0;

  var sumSquares = 0.0;
  for (final sample in samples) {
    sumSquares += sample * sample;
  }

  return math.sqrt(sumSquares / samples.length).clamp(0.0, 1.0).toDouble();
}
