import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dayline_app/core/stt/stt_asset_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extractZipBytes validates manifest checksums', () async {
    final dir = await Directory.systemTemp.createTemp('dayline-stt-assets-');
    addTearDown(() => dir.delete(recursive: true));

    final zipBytes = _zipWithManifest({
      'tokens.txt': utf8.encode('a\nb\n'),
      'life_keywords.txt': utf8.encode('跑步\n咖啡\n'),
    });

    await SttAssetExtractor.extractZipBytes(zipBytes, dir);

    expect(await File('${dir.path}/tokens.txt').readAsString(), 'a\nb\n');
    expect(await SttAssetExtractor.isValid(dir), isTrue);
  });

  test('isValid fails when a file checksum changes', () async {
    final dir = await Directory.systemTemp.createTemp('dayline-stt-assets-');
    addTearDown(() => dir.delete(recursive: true));

    final zipBytes = _zipWithManifest({
      'tokens.txt': utf8.encode('a\nb\n'),
    });

    await SttAssetExtractor.extractZipBytes(zipBytes, dir);
    await File('${dir.path}/tokens.txt').writeAsString('changed');

    expect(await SttAssetExtractor.isValid(dir), isFalse);
  });
}

List<int> _zipWithManifest(Map<String, List<int>> files) {
  final archive = Archive();
  final manifest = <String, String>{};

  for (final entry in files.entries) {
    manifest[entry.key] = sha256.convert(entry.value).toString();
    archive.addFile(
      ArchiveFile(entry.key, entry.value.length, entry.value),
    );
  }

  final manifestBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert({
      'version': 'test',
      'files': manifest,
    }),
  );
  archive.addFile(
    ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
  );

  return ZipEncoder().encode(archive);
}
