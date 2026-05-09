import 'dart:typed_data';

import 'package:dayline_app/core/stt/stt_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pcm16ToFloat32 converts little-endian signed samples', () {
    final bytes = Uint8List.fromList([
      0x00, 0x00, // 0
      0xff, 0x7f, // 32767
      0x00, 0x80, // -32768
      0x00, 0x40, // 16384
    ]);

    final samples = pcm16ToFloat32(bytes);

    expect(samples, hasLength(4));
    expect(samples[0], 0);
    expect(samples[1], closeTo(32767 / 32768, 0.00001));
    expect(samples[2], -1);
    expect(samples[3], closeTo(0.5, 0.00001));
  });

  test('pcm16ToFloat32 ignores a trailing incomplete byte', () {
    final samples = pcm16ToFloat32(Uint8List.fromList([0x00, 0x40, 0xff]));

    expect(samples, hasLength(1));
    expect(samples.single, closeTo(0.5, 0.00001));
  });

  test('rmsAudioLevel returns normalized level for waveform UI', () {
    final silence = Float32List.fromList([0, 0, 0, 0]);
    final voice = Float32List.fromList([0.5, -0.5, 0.5, -0.5]);

    expect(rmsAudioLevel(silence), 0);
    expect(rmsAudioLevel(voice), closeTo(0.5, 0.00001));
  });
}
