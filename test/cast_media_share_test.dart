import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/cast_media_share.dart';
import 'package:reelbox/media/segmented_download.dart';

void main() {
  final original = <String, dynamic>{
    'url': 'https://authorized.invalid/synthetic.mp4',
    'title': 'Synthetic fixture (not a decoder test)',
    'contentType': 'video/mp4',
    'positionMs': 1250,
    'subtitleUrl': 'https://authorized.invalid/not-webvtt.srt',
  };

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cast-share-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('explicit local-file lease serves only the exact file and revokes without deleting media', () async {
    // Synthetic bytes exercise HTTP ownership, not audiovisual decoding.
    final video = await File('${root.path}/synthetic.mp4')
        .writeAsBytes([0, 1, 2, 3, 4, 5]);
    await File('${root.path}/private.txt').writeAsString('do not share');
    final lease = await CastMediaShare.prepare(
      payload: original,
      localFile: video.path,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(lease.close);
    final url = Uri.parse(lease.payload['url'] as String);
    expect(url.scheme, 'http');
    expect(url.pathSegments.first.length, greaterThanOrEqualTo(32));
    expect((await fetch(url)).bytes, [0, 1, 2, 3, 4, 5]);
    expect((await fetch(url, range: 'bytes=2-4')).bytes, [2, 3, 4]);
    for (final forbidden in [
      url.resolve('./'),
      url.resolve('private.txt'),
      url.resolve('package.json'),
      url.replace(path: '/media.mp4'),
    ]) {
      expect((await fetch(forbidden)).status, 404);
    }
    expect(lease.payload['title'], original['title']);
    expect(lease.payload['positionMs'], 1250);
    expect(original['url'], startsWith('https://'));
    await Future.wait([lease.close(), lease.close()]);
    await expectLater(fetch(url), throwsA(isA<SocketException>()));
    expect(await video.readAsBytes(), [0, 1, 2, 3, 4, 5]);
    expect(
      await File('${root.path}/private.txt').readAsString(),
      'do not share',
    );
  });

  test('remote video plus selected text serves actual UTF8 WebVTT only and deletes disposable files', () async {
    final before = await sessionTemps();
    final lease = await CastMediaShare.prepare(
      payload: original,
      subtitleText: '1\n00:00:01,000 --> 00:00:02,000\nسلام',
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(lease.close);
    expect(lease.payload['url'], original['url']);
    final url = Uri.parse(lease.payload['subtitleUrl'] as String);
    final response = await fetch(url);
    expect(response.type, startsWith('text/vtt'));
    expect(
      utf8.decode(response.bytes),
      'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nسلام\n\n',
    );
    final owned = (await sessionTemps()).difference(before);
    expect(owned, hasLength(1));
    expect(owned.single.startsWith(root.path), isFalse);
    expect(
      (await Directory(owned.single).list().toList()).single.path,
      endsWith('.vtt'),
    );
    await lease.close();
    expect(await sessionTemps(), before);
    await expectLater(fetch(url), throwsA(isA<SocketException>()));
  });

  test('local file and selected text share separate actual VTT and media resources', () async {
    final video = await File('${root.path}/synthetic.webm')
        .writeAsString('synthetic media fixture');
    final lease = await CastMediaShare.prepare(
      payload: original,
      localFile: video.path,
      subtitleText: 'WEBVTT\n\n00:00.000 --> 00:01.000\n<b>caption</b>',
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(lease.close);
    final videoUri = Uri.parse(lease.payload['url'] as String);
    final subUri = Uri.parse(lease.payload['subtitleUrl'] as String);
    expect(subUri.pathSegments.first, videoUri.pathSegments.first);
    expect(subUri, isNot(videoUri));
    expect(utf8.decode((await fetch(subUri)).bytes), contains('\ncaption\n'));
    await lease.close();
    expect(await video.exists(), isTrue);
  });

  test('invalid local selections fail rather than quietly loading the remote fallback', () async {
    final empty = await File('${root.path}/empty.mp4').create();
    final unsupported = await File('${root.path}/notes.txt')
        .writeAsString('not video');
    for (final path in [
      'relative.mp4',
      '${root.path}/missing.mp4',
      root.path,
      empty.path,
      unsupported.path,
    ]) {
      await expectLater(
        CastMediaShare.prepare(
          payload: original,
          localFile: path,
          bindAddress: InternetAddress.loopbackIPv4,
        ),
        throwsA(
          anyOf(
            isA<ArgumentError>(),
            isA<FileSystemException>(),
            isA<UnsupportedError>(),
          ),
        ),
      );
    }
  });

  test('unsupported selected subtitles and failed server preparation leave no temp data', () async {
    final before = await sessionTemps();
    await expectLater(
      CastMediaShare.prepare(
        payload: original,
        subtitleText: '<tt>unsupported</tt>',
        bindAddress: InternetAddress.loopbackIPv4,
      ),
      throwsFormatException,
    );
    expect(await sessionTemps(), before);
    await expectLater(
      CastMediaShare.prepare(
        payload: original,
        subtitleText: '1\n00:00:00,000 --> 00:00:01,000\nSynthetic',
        bindAddress: InternetAddress.loopbackIPv4,
        advertisedHost: '8.8.8.8',
      ),
      throwsArgumentError,
    );
    expect(await sessionTemps(), before);
  });

  test('complete indexed package shares only rewritten manifests and validated resources', () async {
    final package = await syntheticPackage(root);
    await File('${package.directory}/private.txt').writeAsString('private');
    final lease = await CastMediaShare.prepare(
      payload: original,
      localFile: package.path,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(lease.close);
    final uri = Uri.parse(lease.payload['url'] as String);
    expect(uri.scheme, 'http');
    expect(
      utf8.decode((await fetch(uri)).bytes),
      package.manifests[package.manifest],
    );
    expect(
      utf8.decode((await fetch(uri.resolve('playlist_1.m3u8'))).bytes),
      contains('resource_0.ts'),
    );
    expect(
      utf8.decode((await fetch(uri.resolve('resource_0.ts'))).bytes),
      'synthetic resource',
    );
    expect((await fetch(uri.resolve('package.json'))).status, 404);
    expect((await fetch(uri.resolve('private.txt'))).status, 404);
    await lease.close();
    expect(await File(package.path).exists(), true);
    expect(await File('${package.directory}/resource_0.ts').exists(), true);
  });
  test('damaged package is not advertised as Cast-ready', () async {
    final package = await syntheticPackage(root);
    await File('${package.directory}/resource_0.ts').writeAsString('corrupt');
    await expectLater(
      CastMediaShare.prepare(
        payload: original,
        localFile: package.path,
        bindAddress: InternetAddress.loopbackIPv4,
      ),
      throwsStateError,
    );
  });
  test(
    'remote-only lease copies payload and never passes through an SRT URL',
    () async {
      final lease = await CastMediaShare.prepare(payload: original);
      expect(lease.payload, {...original}..remove('subtitleUrl'));
      expect(original['subtitleUrl'], endsWith('.srt'));
      await lease.close();
      await lease.close();
    },
  );
  test(
    'public injectable lease constructor closes its resource only once',
    () async {
      var closed = 0;
      final lease = CastMediaLease(
        payload: original,
        onClose: () async {
          closed++;
        },
      );
      await Future.wait([lease.close(), lease.close()]);
      expect(closed, 1);
      expect(lease.payload, original);
      expect(identical(lease.payload, original), isFalse);
    },
  );
}

Future<OfflinePackage> syntheticPackage(Directory root) async {
  final dir = await Directory('${root.path}/pkg').create();
  final bytes = utf8.encode('synthetic resource');
  final package = OfflinePackage(
    id: 'pkg',
    url: 'https://authorized.invalid/root.m3u8',
    directory: dir.path,
    manifest: 'playlist_0.m3u8',
    resources: [
      OfflineResource(
        url: 'https://authorized.invalid/segment.ts',
        filename: 'resource_0.ts',
        bytes: bytes.length,
        digest: sha256.convert(bytes).toString(),
      ),
    ],
    manifests: {
      'playlist_0.m3u8':
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\nplaylist_1.m3u8\n',
      'playlist_1.m3u8': '#EXTM3U\n#EXTINF:1,\nresource_0.ts\n#EXT-X-ENDLIST\n',
    },
    status: 'complete',
  );
  await File('${dir.path}/resource_0.ts').writeAsBytes(bytes);
  for (final entry in package.manifests.entries) {
    await File('${dir.path}/${entry.key}').writeAsString(entry.value);
  }
  await File('${dir.path}/package.json')
      .writeAsString(jsonEncode(package.toJson()));
  return package;
}

Future<({int status, List<int> bytes, String type})> fetch(
  Uri uri, {
  String? range,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(uri);
    if (range != null) request.headers.set('range', range);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (
      status: response.statusCode,
      bytes: bytes,
      type: response.headers.value('content-type') ?? '',
    );
  } finally {
    client.close(force: true);
  }
}

Future<Set<String>> sessionTemps() async =>
    (await Directory.systemTemp
            .list(followLinks: false)
            .where(
              (f) =>
                  f is Directory &&
                  f.uri.pathSegments
                      .where((s) => s.isNotEmpty)
                      .last
                      .startsWith('reelbox-cast-'),
            )
            .toList())
        .map((f) => f.path)
        .toSet();
