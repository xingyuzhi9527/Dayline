import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const senseVoiceModelArchiveUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
    'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2';

class SttAssetPaths {
  const SttAssetPaths(this.root);

  final Directory root;

  String get senseVoiceModel => p.join(root.path, 'model.int8.onnx');
  String get tokens => p.join(root.path, 'tokens.txt');
  String get modelVersion => root.path.split(Platform.pathSeparator).last;
}

class SttAssetManager {
  const SttAssetManager({
    this.directoryName = 'sense_voice_small_zh',
    this.archiveUrl = senseVoiceModelArchiveUrl,
    this.archiveSha256,
  });

  final String directoryName;
  final String archiveUrl;
  final String? archiveSha256;

  Future<SttAssetPaths> ensureReady() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory(
      p.join(documentsDir.path, 'stt_models', directoryName),
    );

    if (await SttAssetExtractor.isValid(outputDir)) {
      return SttAssetPaths(outputDir);
    }

    if (await outputDir.exists()) {
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

    final tempDir = await Directory.systemTemp.createTemp('dayline-stt-');
    try {
      final archiveFile = File(p.join(tempDir.path, 'sense_voice.tar.bz2'));
      await SttModelDownloader.download(
        Uri.parse(archiveUrl),
        archiveFile,
        expectedSha256: archiveSha256,
      );

      await compute(
        _extractSenseVoiceArchiveInBackground,
        _SttAssetExtractionJob(archiveFile.path, outputDir.path),
      );

      await _writeInstallMetadata(outputDir);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }

    if (!await SttAssetExtractor.isValid(outputDir)) {
      throw StateError('SenseVoice 模型文件校验失败。');
    }

    return SttAssetPaths(outputDir);
  }

  Future<void> _writeInstallMetadata(Directory outputDir) async {
    final metadataFile = File(p.join(outputDir.path, 'source.json'));
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'model': 'SenseVoice-Small INT8',
        'archiveUrl': archiveUrl,
        if (archiveSha256 != null) 'archiveSha256': archiveSha256,
        'installedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }
}

class SttModelDownloader {
  const SttModelDownloader._();

  static Future<void> download(
    Uri uri,
    File outputFile, {
    String? expectedSha256,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('下载 SenseVoice 模型失败：HTTP ${response.statusCode}');
      }

      await outputFile.parent.create(recursive: true);
      final sink = outputFile.openWrite();

      try {
        await for (final chunk in response) {
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }

      final actualSha256 = (await sha256.bind(outputFile.openRead()).first)
          .toString();
      if (expectedSha256 != null && actualSha256 != expectedSha256) {
        await outputFile.delete().catchError((_) => outputFile);
        throw StateError('SenseVoice 模型包 SHA256 校验失败。');
      }
    } finally {
      client.close(force: true);
    }
  }
}

@immutable
class _SttAssetExtractionJob {
  const _SttAssetExtractionJob(this.archivePath, this.outputPath);

  final String archivePath;
  final String outputPath;
}

Future<void> _extractSenseVoiceArchiveInBackground(_SttAssetExtractionJob job) {
  return SttAssetExtractor.extractTarBz2File(
    File(job.archivePath),
    Directory(job.outputPath),
  );
}

class SttAssetExtractor {
  static const modelFileName = 'model.int8.onnx';
  static const tokensFileName = 'tokens.txt';
  static const _requiredFiles = {modelFileName, tokensFileName};

  static Future<void> extractTarBz2File(
    File archiveFile,
    Directory outputDir,
  ) async {
    final compressed = await archiveFile.readAsBytes();
    return extractTarBz2Bytes(compressed, outputDir);
  }

  static Future<void> extractTarBz2Bytes(
    List<int> bytes,
    Directory outputDir,
  ) async {
    final tarBytes = BZip2Decoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tarBytes);
    await outputDir.create(recursive: true);

    final extracted = <String>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;

      final fileName = p.basename(entry.name);
      if (!_requiredFiles.contains(fileName)) continue;

      final safePath = _safeOutputPath(outputDir, fileName);
      if (safePath == null) continue;

      final bytes = entry.readBytes();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('无法读取 SenseVoice 模型包内的 ${entry.name}');
      }

      final file = File(safePath);
      await file.writeAsBytes(bytes, flush: true);
      extracted.add(fileName);
    }

    if (!extracted.containsAll(_requiredFiles)) {
      throw StateError('SenseVoice 模型包缺少 model.int8.onnx 或 tokens.txt。');
    }
  }

  static Future<bool> isValid(Directory outputDir) async {
    for (final fileName in _requiredFiles) {
      final safePath = _safeOutputPath(outputDir, fileName);
      if (safePath == null) return false;

      final file = File(safePath);
      if (!await file.exists()) return false;
      if (await file.length() == 0) return false;
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
