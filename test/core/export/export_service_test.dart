import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/export/export_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory rootDir;

  setUp(() async {
    rootDir = await Directory.systemTemp.createTemp('liflow-export-');
  });

  tearDown(() async {
    if (await rootDir.exists()) await rootDir.delete(recursive: true);
  });

  test('saveFile creates its directory and commits without sidecars', () async {
    final exportDir = p.join(rootDir.path, 'nested', 'exports');

    final location = await ExportService.saveFile(
      '# Daily export',
      'daily.md',
      exportDir,
    );

    final target = File(location);
    expect(await target.readAsString(), '# Daily export');
    expect(await File('$location.liflow-tmp').exists(), isFalse);
    expect(await File('$location.liflow-backup').exists(), isFalse);
  });

  test('saveFile replaces an existing export and removes sidecars', () async {
    final target = File(p.join(rootDir.path, 'daily.md'));
    await target.writeAsString('previous export');

    final location = await ExportService.saveFile(
      'replacement export',
      target.uri.pathSegments.last,
      rootDir.path,
    );

    expect(location, target.path);
    expect(await target.readAsString(), 'replacement export');
    expect(await File('${target.path}.liflow-tmp').exists(), isFalse);
    expect(await File('${target.path}.liflow-backup').exists(), isFalse);
  });

  test('saveFile repairs an interrupted replacement before writing', () async {
    final target = File(p.join(rootDir.path, 'daily.md'));
    final backup = File('${target.path}.liflow-backup');
    final temporary = File('${target.path}.liflow-tmp');
    await target.writeAsString('valid previous export');
    await target.rename(backup.path);
    await temporary.writeAsString('truncated replacement');

    await ExportService.saveFile('fresh export', 'daily.md', rootDir.path);

    expect(await target.readAsString(), 'fresh export');
    expect(await temporary.exists(), isFalse);
    expect(await backup.exists(), isFalse);
  });
}
