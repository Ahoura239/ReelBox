import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/state/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cache size and clear are limited to disposable cache, not downloads/library/symlinks', () async {
    final sandbox = await Directory('${Directory.current.path}/.dart_tool')
        .createTemp('next-library-cache-');
    addTearDown(() => sandbox.delete(recursive: true));
    final cache = await Directory('${sandbox.path}/reelbox-cache').create();
    final downloads = await Directory('${sandbox.path}/downloads').create();
    final completed = await File('${downloads.path}/complete.mp4')
        .writeAsBytes([1, 2, 3]);
    final library = await File('${sandbox.path}/library.json')
        .writeAsString('private');
    await File('${cache.path}/artwork').writeAsBytes([1, 2, 3, 4]);
    await Link('${cache.path}/outside').create(downloads.path);
    final service = CacheService(directory: () async => cache);
    expect((await service.measure()).diskBytes, 4);
    await service.clear();
    expect((await service.measure()).diskBytes, 0);
    expect(await completed.readAsBytes(), [1, 2, 3]);
    expect(await library.readAsString(), 'private');
  });
}
