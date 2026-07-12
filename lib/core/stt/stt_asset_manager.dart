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
    Future<void> Function(String assetPath, File outputFile)? assetFileWriter,
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _assetBytesLoader = assetBytesLoader,
       _assetFileWriter =
           assetFileWriter ??
           (assetBytesLoader == null ? _copyBundledAssetToFile : null);

  final String directoryName;
  final String archiveUrl;
  final String? archiveSha256;
  final String bundledArchiveAssetPath;
  final String? bundledArchiveSha256;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<List<int>> Function(String assetPath)? _assetBytesLoader;
  final Future<void> Function(String assetPath, File outputFile)?
  _assetFileWriter;
  Future<SttAssetPaths>? _ensureReadyInFlight;

  Future<SttAssetPaths> ensureReady() {
    final inFlight = _ensureReadyInFlight;
    if (inFlight != null) return inFlight;

    late final Future<SttAssetPaths> future;
    future = _ensureReadyInternal().whenComplete(() {
      if (identical(_ensureReadyInFlight, future)) {
        _ensureReadyInFlight = null;
      }
    });
    _ensureReadyInFlight = future;
    return future;
  }

  Future<SttAssetPaths> _ensureReadyInternal() async {
    final documentsDir = await _documentsDirectoryProvider();
    final modelsDir = Directory(p.join(documentsDir.path, 'stt_models'));
    await modelsDir.create(recursive: true);
    final outputDir = Directory(p.join(modelsDir.path, directoryName));

    await _recoverInterruptedInstall(modelsDir, outputDir);
    await SttAssetExtractor.repairLegacyInstall(outputDir);
    if (await SttAssetExtractor.isValid(outputDir)) {
      return SttAssetPaths(outputDir);
    }

    final stagingDir = Directory(
      '${outputDir.path}.installing-${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      await stagingDir.create(recursive: true);
      final installSource =
          await _installBundledArchive(stagingDir) ??
          await _downloadArchive(stagingDir);

      await _writeInstallMetadata(stagingDir, installSource: installSource);

      if (!await SttAssetExtractor.isValid(stagingDir)) {
        throw StateError('SenseVoice 模型文件校验失败。');
      }

      await _publishInstall(stagingDir, outputDir);
      return SttAssetPaths(outputDir);
    } finally {
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    }
  }

  Future<void> _recoverInterruptedInstall(
    Directory modelsDir,
    Directory outputDir,
  ) async {
    final backupDir = Directory('${outputDir.path}.backup');
    final stagingDirs = <Directory>[];
    await for (final entity in modelsDir.list()) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('${p.basename(outputDir.path)}.installing-')) {
        stagingDirs.add(entity);
      }
    }

    await SttAssetExtractor.repairLegacyInstall(backupDir);
    final outputValid = await SttAssetExtractor.isValid(outputDir);
    if (!outputValid && await SttAssetExtractor.isValid(backupDir)) {
      if (await outputDir.exists()) {
        await outputDir.delete(recursive: true);
      }
      await backupDir.rename(outputDir.path);
    } else if (outputValid && await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }

    if (!await SttAssetExtractor.isValid(outputDir)) {
      for (final stagingDir in stagingDirs) {
        if (await SttAssetExtractor.isValid(stagingDir)) {
          if (await outputDir.exists()) {
            await outputDir.delete(recursive: true);
          }
          await stagingDir.rename(outputDir.path);
          break;
        }
      }
    }

    for (final stagingDir in stagingDirs) {
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    }
  }

  Future<void> _publishInstall(
    Directory stagingDir,
    Directory outputDir,
  ) async {
    final backupDir = Directory('${outputDir.path}.backup');
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }

    var movedPrevious = false;
    try {
      if (await outputDir.exists()) {
        await outputDir.rename(backupDir.path);
        movedPrevious = true;
      }
      await stagingDir.rename(outputDir.path);
      if (movedPrevious && await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
    } catch (_) {
      if (!await outputDir.exists() &&
          movedPrevious &&
          await backupDir.exists()) {
        await backupDir.rename(outputDir.path);
      }
      rethrow;
    }
  }

  Future<String?> _installBundledArchive(Directory outputDir) async {
    final tempDir = await Directory.systemTemp.createTemp('liflow-stt-asset-');
    try {
      final archiveFile = File(
        p.join(tempDir.path, p.basename(bundledArchiveAssetPath)),
      );
      final fileWriter = _assetFileWriter;
      if (fileWriter != null) {
        await fileWriter(bundledArchiveAssetPath, archiveFile);
      } else {
        final bytesLoader = _assetBytesLoader;
        if (bytesLoader == null) {
          throw StateError('SenseVoice 预置模型包读取器未配置。');
        }
        final bytes = await bytesLoader(bundledArchiveAssetPath);
        await archiveFile.writeAsBytes(bytes, flush: true);
      }

      final sha256Hex = await _sha256File(archiveFile);
      final expectedBundledSha256 = bundledArchiveSha256;
      if (expectedBundledSha256 != null &&
          sha256Hex.toLowerCase() != expectedBundledSha256.toLowerCase()) {
        throw StateError('SenseVoice 预置模型包 SHA256 校验失败。');
      }
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
    final tempDir = await Directory.systemTemp.createTemp('liflow-stt-');
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
      final output = await outputFile.open(mode: FileMode.write);

      try {
        await for (final chunk in response) {
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }

      final actualSha256 = await _sha256File(outputFile);
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

Future<void> _extractSenseVoiceArchiveInBackground(_SttAssetExtractionJob job) {
  return SttAssetExtractor.extractTarBz2File(
    File(job.archivePath),
    Directory(job.outputPath),
  );
}

Future<void> _copyBundledAssetToFile(String assetPath, File outputFile) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await _sttAssetChannel.invokeMethod<void>('copyAssetToFile', {
        'assetPath': assetPath,
        'outputPath': outputFile.path,
      });
      return;
    } on MissingPluginException {
      // Desktop tests and older Android shells use the AssetBundle fallback.
    }
  }

  // AssetBundle exposes the bundled file as ByteData. Keep the existing
  // loader contract, but stream bounded views to disk so later hashing and
  // extraction never create another full-size copy.
  final byteData = await rootBundle.load(assetPath);
  final bytes = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  final handle = await outputFile.open(mode: FileMode.write);
  try {
    const chunkSize = 1024 * 1024;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length).toInt();
      // Await each write so IOSink-style buffering cannot retain a second
      // full archive while the asset is being copied.
      await handle.writeFrom(bytes, offset, end);
    }
    await handle.flush();
  } finally {
    await handle.close();
  }
}

const _sttAssetChannel = MethodChannel('liflow/stt_assets');

Future<String> _sha256File(File file) async {
  return (await sha256.bind(file.openRead()).first).toString();
}

class SttAssetExtractor {
  static const modelFileName = 'model.int8.onnx';
  static const tokensFileName = 'tokens.txt';
  static const integrityFileName = 'integrity.json';
  static const _requiredFiles = {modelFileName, tokensFileName};

  static Future<void> extractTarBz2File(
    File archiveFile,
    Directory outputDir,
  ) async {
    final tarFile = File('${archiveFile.path}.tar');
    try {
      await _decodeBzip2ToTar(InputFileStream(archiveFile.path), tarFile);
      await _extractTarFile(tarFile, outputDir);
    } finally {
      if (await tarFile.exists()) {
        await tarFile.delete();
      }
    }
  }

  static Future<void> extractTarBz2Bytes(
    List<int> bytes,
    Directory outputDir,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('liflow-stt-tar-');
    final tarFile = File(p.join(tempDir.path, 'model.tar'));
    try {
      await _decodeBzip2ToTar(InputMemoryStream(bytes), tarFile);
      await _extractTarFile(tarFile, outputDir);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  static Future<void> _decodeBzip2ToTar(InputStream input, File tarFile) async {
    final output = OutputFileStream(tarFile.path);
    try {
      final decoded = BZip2Decoder().decodeStream(input, output, verify: true);
      if (!decoded) {
        throw StateError('无法解压 SenseVoice 模型包。');
      }
    } finally {
      input.closeSync();
      output.closeSync();
    }
  }

  static Future<void> _extractTarFile(File tarFile, Directory outputDir) async {
    await outputDir.create(recursive: true);
    final integrityFile = File(p.join(outputDir.path, integrityFileName));
    if (await integrityFile.exists()) {
      await integrityFile.delete();
    }

    final extracted = <String>{};
    final expectedSizes = <String, int>{};
    final input = InputFileStream(tarFile.path);
    try {
      TarDecoder().decodeStream(
        input,
        // Keep archive entries as file-backed streams. Calling readBytes here
        // would materialize the 160MB model in the isolate heap again.
        storeData: true,
        callback: (entry) {
          if (!entry.isFile) return;

          final fileName = p.basename(entry.name);
          if (!_requiredFiles.contains(fileName)) return;

          final safePath = _safeOutputPath(outputDir, fileName);
          if (safePath == null) return;

          final file = File(safePath);
          final output = OutputFileStream(safePath);
          try {
            entry.writeContent(output, freeMemory: true);
          } finally {
            output.closeSync();
          }

          if (file.lengthSync() == 0) {
            throw StateError('无法读取 SenseVoice 模型包内的 ${entry.name}');
          }
          extracted.add(fileName);
          expectedSizes[fileName] = entry.size;
          if (file.lengthSync() != entry.size) {
            throw StateError('SenseVoice 模型文件 ${entry.name} 长度校验失败。');
          }
        },
      );
    } finally {
      input.closeSync();
    }

    if (!extracted.containsAll(_requiredFiles)) {
      throw StateError('SenseVoice 模型包缺少 model.int8.onnx 或 tokens.txt。');
    }

    await integrityFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'files': expectedSizes}),
      flush: true,
    );
  }

  static Future<bool> isValid(Directory outputDir) async {
    final integrityFile = File(p.join(outputDir.path, integrityFileName));
    if (!await integrityFile.exists()) return false;

    Map<String, dynamic> manifest;
    try {
      manifest =
          jsonDecode(await integrityFile.readAsString())
              as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    final expectedSizes = manifest['files'];
    if (expectedSizes is! Map) return false;

    for (final fileName in _requiredFiles) {
      final safePath = _safeOutputPath(outputDir, fileName);
      if (safePath == null) return false;

      final file = File(safePath);
      if (!await file.exists()) return false;
      final expectedSize = expectedSizes[fileName];
      if (expectedSize is! num || expectedSize <= 0) return false;
      if (await file.length() != expectedSize) return false;
    }

    return true;
  }

  static Future<void> repairLegacyInstall(Directory outputDir) async {
    final integrityFile = File(p.join(outputDir.path, integrityFileName));
    if (await integrityFile.exists()) return;

    final expectedSizes = <String, int>{};
    for (final fileName in _requiredFiles) {
      final safePath = _safeOutputPath(outputDir, fileName);
      if (safePath == null) return;
      final file = File(safePath);
      if (!await file.exists()) return;
      final length = await file.length();
      if (length <= 0) return;
      expectedSizes[fileName] = length;
    }

    await outputDir.create(recursive: true);
    await integrityFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'files': expectedSizes}),
      flush: true,
    );
  }

  static String? _safeOutputPath(Directory outputDir, String relativePath) {
    if (relativePath.trim().isEmpty) return null;
    final normalized = p.normalize(relativePath).replaceAll('\\', '/');
    if (p.isAbsolute(normalized)) return null;
    if (normalized == '..' || normalized.startsWith('../')) return null;
    return p.join(outputDir.path, normalized);
  }
}
