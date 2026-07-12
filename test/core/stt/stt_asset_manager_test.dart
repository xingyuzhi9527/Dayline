import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:liflow_app/core/stt/stt_asset_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'extractTarBz2Bytes extracts SenseVoice model files from package root',
    () async {
      final dir = await Directory.systemTemp.createTemp('liflow-stt-assets-');
      addTearDown(() => dir.delete(recursive: true));

      final bytes = _tarBz2WithFiles({
        'sherpa-onnx-sense-voice/model.int8.onnx': utf8.encode('onnx-bytes'),
        'sherpa-onnx-sense-voice/tokens.txt': utf8.encode('a\nb\n'),
        'sherpa-onnx-sense-voice/README.md': utf8.encode('ignore me'),
      });

      await SttAssetExtractor.extractTarBz2Bytes(bytes, dir);

      expect(
        await File('${dir.path}/model.int8.onnx').readAsString(),
        'onnx-bytes',
      );
      expect(await File('${dir.path}/tokens.txt').readAsString(), 'a\nb\n');
      expect(await File('${dir.path}/README.md').exists(), isFalse);
      expect(await SttAssetExtractor.isValid(dir), isTrue);
    },
  );

  test(
    'extractTarBz2Bytes fails when required SenseVoice files are missing',
    () async {
      final dir = await Directory.systemTemp.createTemp('liflow-stt-assets-');
      addTearDown(() => dir.delete(recursive: true));

      final bytes = _tarBz2WithFiles({
        'sherpa-onnx-sense-voice/tokens.txt': utf8.encode('a\nb\n'),
      });

      await expectLater(
        SttAssetExtractor.extractTarBz2Bytes(bytes, dir),
        throwsStateError,
      );
      expect(await SttAssetExtractor.isValid(dir), isFalse);
    },
  );

  test(
    'SttAssetManager installs bundled archive before falling back to network',
    () async {
      final docsDir = await Directory.systemTemp.createTemp('liflow-stt-docs-');
      addTearDown(() => docsDir.delete(recursive: true));

      final bundledBytes = _tarBz2WithFiles({
        'sherpa-onnx-sense-voice/model.int8.onnx': utf8.encode('onnx-bytes'),
        'sherpa-onnx-sense-voice/tokens.txt': utf8.encode('a\nb\n'),
      });

      final manager = SttAssetManager(
        documentsDirectoryProvider: () async => docsDir,
        assetBytesLoader: (_) async => bundledBytes,
      );

      final paths = await manager.ensureReady();

      expect(await File(paths.senseVoiceModel).readAsString(), 'onnx-bytes');
      expect(await File(paths.tokens).readAsString(), 'a\nb\n');

      final metadata =
          jsonDecode(
                await File('${paths.root.path}/source.json').readAsString(),
              )
              as Map<String, dynamic>;
      expect(metadata['installSource'], 'bundled-asset');
      expect(metadata['model'], 'SenseVoice-Small INT8');
    },
  );

  test(
    'SttAssetManager supports a file writer without materializing a loader list',
    () async {
      final docsDir = await Directory.systemTemp.createTemp('liflow-stt-docs-');
      addTearDown(() => docsDir.delete(recursive: true));

      final bundledBytes = _tarBz2WithFiles({
        'sherpa-onnx-sense-voice/model.int8.onnx': utf8.encode('onnx-bytes'),
        'sherpa-onnx-sense-voice/tokens.txt': utf8.encode('a\nb\n'),
      });

      final manager = SttAssetManager(
        documentsDirectoryProvider: () async => docsDir,
        assetBytesLoader: (_) async =>
            throw StateError('byte loader should not be called'),
        assetFileWriter: (_, outputFile) async {
          await outputFile.writeAsBytes(bundledBytes, flush: true);
        },
      );

      final paths = await manager.ensureReady();

      expect(await File(paths.senseVoiceModel).readAsString(), 'onnx-bytes');
      expect(await File(paths.tokens).readAsString(), 'a\nb\n');
    },
  );

  test('isValid rejects a non-empty truncated model file', () async {
    final dir = await Directory.systemTemp.createTemp('liflow-stt-assets-');
    addTearDown(() => dir.delete(recursive: true));

    await SttAssetExtractor.extractTarBz2Bytes(
      _tarBz2WithFiles({
        'model.int8.onnx': utf8.encode('complete-model'),
        'tokens.txt': utf8.encode('a\nb\n'),
      }),
      dir,
    );
    await File('${dir.path}/model.int8.onnx').writeAsString('x', flush: true);

    expect(await SttAssetExtractor.isValid(dir), isFalse);
  });

  test(
    'repairLegacyInstall accepts a complete pre-manifest model directory',
    () async {
      final docsDir = await Directory.systemTemp.createTemp('liflow-stt-docs-');
      addTearDown(() => docsDir.delete(recursive: true));
      final outputDir = Directory(
        '${docsDir.path}/stt_models/sense_voice_small_zh',
      );
      await outputDir.create(recursive: true);
      await File(
        '${outputDir.path}/model.int8.onnx',
      ).writeAsString('legacy-model', flush: true);
      await File(
        '${outputDir.path}/tokens.txt',
      ).writeAsString('a\nb\n', flush: true);
      var writerCalls = 0;

      final manager = SttAssetManager(
        documentsDirectoryProvider: () async => docsDir,
        assetFileWriter: (_, _) async {
          writerCalls += 1;
          throw StateError('legacy model should not reinstall');
        },
      );

      final paths = await manager.ensureReady();

      expect(writerCalls, 0);
      expect(await File(paths.senseVoiceModel).readAsString(), 'legacy-model');
      expect(await File('${outputDir.path}/integrity.json').exists(), isTrue);
      expect(await SttAssetExtractor.isValid(outputDir), isTrue);
    },
  );

  test('SttAssetManager shares one concurrent install', () async {
    final docsDir = await Directory.systemTemp.createTemp('liflow-stt-docs-');
    addTearDown(() => docsDir.delete(recursive: true));
    final bundledBytes = _tarBz2WithFiles({
      'model.int8.onnx': utf8.encode('onnx-bytes'),
      'tokens.txt': utf8.encode('a\nb\n'),
    });
    var writerCalls = 0;

    final manager = SttAssetManager(
      documentsDirectoryProvider: () async => docsDir,
      assetFileWriter: (_, outputFile) async {
        writerCalls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await outputFile.writeAsBytes(bundledBytes, flush: true);
      },
    );

    final paths = await Future.wait([
      manager.ensureReady(),
      manager.ensureReady(),
    ]);

    expect(writerCalls, 1);
    expect(paths[0].root.path, paths[1].root.path);
    expect(await SttAssetExtractor.isValid(paths[0].root), isTrue);
  });

  test(
    'SttAssetManager restores a valid backup after interrupted publish',
    () async {
      final docsDir = await Directory.systemTemp.createTemp('liflow-stt-docs-');
      addTearDown(() => docsDir.delete(recursive: true));
      final modelsDir = Directory('${docsDir.path}/stt_models');
      final outputDir = Directory('${modelsDir.path}/sense_voice_small_zh');
      final backupDir = Directory('${outputDir.path}.backup');
      await outputDir.create(recursive: true);
      await File('${outputDir.path}/model.int8.onnx').writeAsString('partial');
      await File('${outputDir.path}/tokens.txt').writeAsString('partial');
      await SttAssetExtractor.extractTarBz2Bytes(
        _tarBz2WithFiles({
          'model.int8.onnx': utf8.encode('recovered-model'),
          'tokens.txt': utf8.encode('a\nb\n'),
        }),
        backupDir,
      );
      var writerCalls = 0;
      final manager = SttAssetManager(
        documentsDirectoryProvider: () async => docsDir,
        assetFileWriter: (_, _) async {
          writerCalls += 1;
          throw StateError('backup recovery should avoid reinstall');
        },
      );

      final paths = await manager.ensureReady();

      expect(writerCalls, 0);
      expect(
        await File(paths.senseVoiceModel).readAsString(),
        'recovered-model',
      );
      expect(await backupDir.exists(), isFalse);
    },
  );

  test('SttAssetManager promotes a complete staging directory', () async {
    final docsDir = await Directory.systemTemp.createTemp('liflow-stt-docs-');
    addTearDown(() => docsDir.delete(recursive: true));
    final modelsDir = Directory('${docsDir.path}/stt_models');
    final outputDir = Directory('${modelsDir.path}/sense_voice_small_zh');
    final stagingDir = Directory('${outputDir.path}.installing-123');
    await outputDir.create(recursive: true);
    await File('${outputDir.path}/model.int8.onnx').writeAsString('partial');
    await File('${outputDir.path}/tokens.txt').writeAsString('partial');
    await SttAssetExtractor.extractTarBz2Bytes(
      _tarBz2WithFiles({
        'model.int8.onnx': utf8.encode('staged-model'),
        'tokens.txt': utf8.encode('a\nb\n'),
      }),
      stagingDir,
    );
    var writerCalls = 0;
    final manager = SttAssetManager(
      documentsDirectoryProvider: () async => docsDir,
      assetFileWriter: (_, _) async {
        writerCalls += 1;
        throw StateError('staging promotion should avoid reinstall');
      },
    );

    final paths = await manager.ensureReady();

    expect(writerCalls, 0);
    expect(await File(paths.senseVoiceModel).readAsString(), 'staged-model');
    expect(await stagingDir.exists(), isFalse);
  });

  test('Android default writer streams through the platform channel', () async {
    final docsDir = await Directory.systemTemp.createTemp('liflow-stt-docs-');
    addTearDown(() => docsDir.delete(recursive: true));
    final bundledBytes = _tarBz2WithFiles({
      'model.int8.onnx': utf8.encode('native-model'),
      'tokens.txt': utf8.encode('a\nb\n'),
    });
    const channel = MethodChannel('liflow/stt_assets');
    var channelCalls = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'copyAssetToFile');
          channelCalls += 1;
          final arguments = Map<String, Object?>.from(call.arguments as Map);
          await File(
            arguments['outputPath']! as String,
          ).writeAsBytes(bundledBytes, flush: true);
          return null;
        });
    final manager = SttAssetManager(
      documentsDirectoryProvider: () async => docsDir,
    );

    final paths = await manager.ensureReady();

    expect(channelCalls, 1);
    expect(await File(paths.senseVoiceModel).readAsString(), 'native-model');
  });
}

List<int> _tarBz2WithFiles(Map<String, List<int>> files) {
  final archive = Archive();

  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }

  final tarBytes = TarEncoder().encodeBytes(archive);
  return BZip2Encoder().encodeBytes(tarBytes);
}
