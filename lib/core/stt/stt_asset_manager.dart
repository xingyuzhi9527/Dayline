import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const senseVoiceModelArchiveUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
    'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2';

const senseVoiceModelArchiveSha256 =
    '7D1EFA2138A65B0B488DF37F8B89E3D91A60676E416F515B952358D83DFD347E';

class SttAssetPaths {
  const SttAssetPaths(this.root);

  final Directory root;

  String get senseVoiceModel => p.join(root.path, 'model.int8.onnx');
  String get tokens => p.join(root.path, 'tokens.txt');
  String get modelVersion => root.path.split(Platform.pathSeparator).last;
}

class SttAssetManager {
  SttAssetManager({
    this.directoryName = 'sense_voice_small_zh',
    this.archiveUrl = senseVoiceModelArchiveUrl,
    this.archiveSha256,
    this.bundledArchiveAssetPath = 'assets/stt/sense_voice_small_zh.tar.bz2',
    this.bundledArchiveSha256,
    Future<Directory> Function()? documentsDirectoryProvider,
    Future<List<int>> Function(String assetPath)? assetBytesLoader,
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _assetBytesLoader = assetBytesLoader ?? _loadAssetBytes;

  final String directoryName;
  final String archiveUrl;
  final String? archiveSha256;
  final String bundledArchiveAssetPath;
  final String? bundledArchiveSha256;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<List<int>> Function(String assetPath) _assetBytesLoader;

  Future<SttAssetPaths> ensureReady() async {
    final documentsDir = await _documentsDirectoryProvider();
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

    final installSource = await _installBundledArchive(outputDir) ??
        await _downloadArchive(outputDir);

    await _writeInstallMetadata(
      outputDir,
      installSource: installSource,
    );

    if (!await SttAssetExtractor.isValid(outputDir)) {
      throw StateError('SenseVoice 模型文件校验失败。');
    }

    return SttAssetPaths(outputDir);
  }

  Future<String?> _installBundledArchive(Directory outputDir) async {
    final tempDir = await Directory.systemTemp.createTemp('dayline-stt-asset-');
    try {
      final bytes = await _assetBytesLoader(bundledArchiveAssetPath);
      final sha256Hex = sha256.convert(bytes).toString();
      final expectedBundledSha256 = bundledArchiveSha256;
      if (expectedBundledSha256 != null &&
          sha256Hex.toLowerCase() != expectedBundledSha256.toLowerCase()) {
        throw StateError('SenseVoice 预置模型包 SHA256 校验失败。');
      }
      final archiveFile = File(
        p.join(tempDir.path, p.basename(bundledArchiveAssetPath)),
      );
      await archiveFile.writeAsBytes(bytes, flush: true);
      await _extractArchiveFile(archiveFile, outputDir);
      return 'bundled-asset';
    } on FlutterError catch (error) {
      if (kDebugMode) {
        debugPrint('SenseVoice bundled asset load failed: $error');
      }
      return null;
    } on FileSystemException catch (error) {
      if (kDebugMode) {
        debugPrint('SenseVoice bundled archive temp write failed: $error');
      }
      return null;
    } on StateError catch (error) {
      if (kDebugMode) {
        debugPrint('SenseVoice bundled archive validation failed: $error');
      }
      return null;
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<String> _downloadArchive(Directory outputDir) async {
    final tempDir = await Directory.systemTemp.createTemp('dayline-stt-');
    try {
      final archiveFile = File(p.join(tempDir.path, 'sense_voice.tar.bz2'));
      await SttModelDownloader.download(
        Uri.parse(archiveUrl),
        archiveFile,
        expectedSha256: archiveSha256,
      );

      await _extractArchiveFile(archiveFile, outputDir);
      return 'download';
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> _extractArchiveFile(File archiveFile, Directory outputDir) {
    return compute(
      _extractSenseVoiceArchiveInBackground,
      _SttAssetExtractionJob(archiveFile.path, outputDir.path),
    );
  }

  Future<void> _writeInstallMetadata(
    Directory outputDir, {
    required String installSource,
  }) async {
    final metadataFile = File(p.join(outputDir.path, 'source.json'));
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'model': 'SenseVoice-Small INT8',
        'archiveUrl': archiveUrl,
        if (archiveSha256 != null) 'archiveSha256': archiveSha256,
        'installSource': installSource,
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
      if (expectedSha256 != null &&
          actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
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

@immutable
Future<void> _extractSenseVoiceArchiveInBackground(_SttAssetExtractionJob job) {
  return SttAssetExtractor.extractTarBz2File(
    File(job.archivePath),
    Directory(job.outputPath),
  );
}

Future<List<int>> _loadAssetBytes(String assetPath) async {
  final byteData = await rootBundle.load(assetPath);
  return byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
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
