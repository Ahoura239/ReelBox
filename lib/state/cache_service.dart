import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class CacheSnapshot {
  const CacheSnapshot({required this.memoryBytes, required this.diskBytes});
  final int memoryBytes, diskBytes;
  int get totalBytes => memoryBytes + diskBytes;
}

/// Disposable cache only. Never sweep the temporary/app-support directories:
/// downloads, pending packages and private library data may also live there.
class CacheService {
  CacheService({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;
  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}/reelbox-cache');

  Future<CacheSnapshot> measure() async {
    var diskBytes = 0;
    if (!kIsWeb) {
      final directory = await _directory();
      // Ignore links even when the cache root itself is one.
      if (await FileSystemEntity.type(directory.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await for (final entry in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (await FileSystemEntity.type(entry.path, followLinks: false) ==
              FileSystemEntityType.file) {
            try {
              diskBytes += await File(entry.path).length();
            } on FileSystemException {
              // An evicted file may disappear during measurement.
            }
          }
        }
      }
    }
    return CacheSnapshot(
      memoryBytes: PaintingBinding.instance.imageCache.currentSizeBytes,
      diskBytes: diskBytes,
    );
  }

  Future<void> clear() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (kIsWeb) return;
    final directory = await _directory();
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    // Only regular files. Do not follow or delete links to other storage.
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (await FileSystemEntity.type(entry.path, followLinks: false) ==
          FileSystemEntityType.file) {
        try {
          await File(entry.path).delete();
        } on FileSystemException {
          if (await File(entry.path).exists()) rethrow;
        }
      }
    }
  }
}
