import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:liflow_app/core/stt/stt_asset_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

      final metadata = jsonDecode(
        await File('${paths.root.path}/source.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(metadata['installSource'], 'bundled-asset');
      expect(metadata['model'], 'SenseVoice-Small INT8');
    },
  );
}

List<int> _tarBz2WithFiles(Map<String, List<int>> files) {
  final archive = Archive();

  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }

  final tarBytes = TarEncoder().encodeBytes(archive);
  return BZip2Encoder().encodeBytes(tarBytes);
}
