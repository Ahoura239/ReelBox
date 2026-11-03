import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/media/download_service.dart';
import 'package:reelbox/media/media_helpers.dart';
import 'package:reelbox/media/media_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaPlatform.channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaPlatform.channel, null);
  });

  for (final type in [
    'mpd', ' MPD ', 'hls', ' HLS ', 'm3u8', 'M3U8', 'dash', ' DASH ',
    'application/dash+xml', 'application/vnd.apple.mpegurl',
    'application/x-mpegURL; charset=UTF-8',
  ]) {
    test('extensionless $type is not a direct-file or external-downloader source', () async {
      final source = MediaSource(url: 'https://example.test/manifest?id=7', type: type);
      expect(isSegmentedMediaSource(source), isTrue);
      final entry = DownloadEntry.fromTask(DownloadTask(
        taskId: 'manifest', url: source.url, filename: 'legacy.mp4',
        metaData: jsonEncode({'titleId': 7, 'title': 'Fixture', 'sourceType': type}),
      ), taskStatus: TaskStatus.failed);
      await expectLater(DownloadService.instance.externalDownloader(entry),
          throwsA(isA<UnsupportedError>().having((e) => e.message, 'message', contains('package'))));
      expect(calls, isEmpty);
      expect(downloadUnsupportedReason(source), isNotNull);
    });
  }

  test('manifest URL extensions override direct type hints', () {
    for (final extension in ['M3U8', 'MPD']) {
      expect(downloadUnsupportedReason(MediaSource(
        url: 'https://example.test/video.$extension?name=movie.mp4', type: 'mp4',
      )), isNotNull);
    }
  });

  test('direct MP4 remains eligible for direct and external download', () async {
    const source = MediaSource(url: 'https://example.test/video.mp4', type: 'mp4');
    expect(downloadUnsupportedReason(source), isNull);
    final entry = DownloadEntry.fromTask(DownloadTask(
      taskId: 'direct', url: source.url, filename: 'video.mp4',
      metaData: jsonEncode({'titleId': 7, 'title': 'Fixture', 'sourceType': 'mp4'}),
    ));
    await DownloadService.instance.externalDownloader(entry);
    expect(calls.map((call) => call.method), ['openDownloader']);
  });
}
