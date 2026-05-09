import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SttAssetPaths {
  const SttAssetPaths(this.root);

  final Directory root;

  String get encoder => p.join(root.path, 'encoder-epoch-20-avg-1-chunk-16-left-128.int8.onnx');
  String get decoder => p.join(root.path, 'decoder-epoch-20-avg-1-chunk-16-left-128.int8.onnx');
  String get joiner => p.join(root.path, 'joiner-epoch-20-avg-1-chunk-16-left-128.int8.onnx');
  String get tokens => p.join(root.path, 'tokens.txt');
  String get bpeModel => p.join(root.path, 'bpe.model');
  String get vadModel => p.join(root.path, 'silero_vad.onnx');
  String get hotwords => p.join(root.path, 'life_keywords.txt');
}

class SttAssetManager {
  const SttAssetManager({
    this.assetZipPath = 'assets/stt/dayline-stt-v2.zip',
    this.directoryName = 'dayline_stt_v2',
  });

  final String assetZipPath;
  final String directoryName;

  Future<SttAssetPaths> ensureReady() async {
    final supportDir = await getApplicationSupportDirectory();
    final outputDir = Directory(p.join(supportDir.path, directoryName));

    if (await SttAssetExtractor.isValid(outputDir)) {
      return SttAssetPaths(outputDir);
    }

    if (await outputDir.exists()) {
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

    final bytes = await rootBundle.load(assetZipPath);
    await compute(
      _extractSttAssetInBackground,
      _SttAssetExtractionJob(
        bytes.buffer.asUint8List(),
        outputDir.path,
      ),
    );

    if (!await SttAssetExtractor.isValid(outputDir)) {
      throw StateError('离线语音模型文件校验失败。');
    }

    return SttAssetPaths(outputDir);
  }
}

@immutable
class _SttAssetExtractionJob {
  const _SttAssetExtractionJob(this.bytes, this.outputPath);

  final Uint8List bytes;
  final String outputPath;
}

Future<void> _extractSttAssetInBackground(_SttAssetExtractionJob job) {
  return SttAssetExtractor.extractZipBytes(
    job.bytes,
    Directory(job.outputPath),
  );
}

class SttAssetExtractor {
  static const manifestFileName = 'manifest.json';

  static Future<void> extractZipBytes(
    List<int> bytes,
    Directory outputDir,
  ) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    await outputDir.create(recursive: true);

    for (final entry in archive) {
      final safePath = _safeOutputPath(outputDir, entry.name);
      if (safePath == null) continue;

      if (entry.isFile) {
        final file = File(safePath);
        await file.parent.create(recursive: true);
        final bytes = entry.readBytes();
        if (bytes == null) {
          throw StateError('无法读取语音模型压缩包内的 ${entry.name}');
        }
        await file.writeAsBytes(bytes, flush: true);
      } else {
        await Directory(safePath).create(recursive: true);
      }
    }
  }

  static Future<bool> isValid(Directory outputDir) async {
    final manifestFile = File(p.join(outputDir.path, manifestFileName));
    if (!await manifestFile.exists()) return false;

    final manifest = jsonDecode(await manifestFile.readAsString());
    if (manifest is! Map<String, Object?>) return false;
    final files = manifest['files'];
    if (files is! Map<String, Object?>) return false;

    for (final entry in files.entries) {
      final relativePath = entry.key;
      final expectedHash = entry.value;
      if (expectedHash is! String) return false;

      final safePath = _safeOutputPath(outputDir, relativePath);
      if (safePath == null) return false;

      final file = File(safePath);
      if (!await file.exists()) return false;

      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (digest != expectedHash) return false;
    }

    return true;
  }

  static String? _safeOutputPath(Directory outputDir, String relativePath) {
    if (relativePath.trim().isEmpty) return null;
    final normalized = p.normalize(relativePath).replaceAll('\\', '/');
    if (p.isAbsolute(normalized)) return null;
    if (normalized == '..' || normalized.startsWith('../')) return null;
    return p.join(outputDir.path, normalized);
  }
}
