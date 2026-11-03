import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/local_media_server.dart';

void main() {
  late Directory root;
  late File video;
  late HttpClient client;
  final sessions = <LocalMediaServer>[];

  setUp(() async {
    root = await Directory(Platform.environment['TMPDIR'] ?? Directory.systemTemp.path)
        .createTemp('reelbox-lan-test-');
    video = await File('${root.path}/movie.mp4').writeAsString('0123456789');
    client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  });

  tearDown(() async {
    client.close(force: true);
    for (final session in sessions) {
      await session.close();
    }
    sessions.clear();
    await root.delete(recursive: true);
  });

  Future<LocalMediaServer> start({File? file, File? subtitle, Map<String, File> extras = const {}}) async {
    final session = await LocalMediaServer.start(
      file: file ?? video,
      subtitle: subtitle,
      extraFiles: extras,
      bindAddress: InternetAddress.loopbackIPv4,
      advertisedHost: '127.0.0.1',
    );
    sessions.add(session);
    return session;
  }

  Future<({HttpClientResponse response, List<int> bytes})> request(
    Uri uri, {String method = 'GET', String? range}
  ) async {
    final request = await client.openUrl(method, uri);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return (response: response, bytes: bytes);
  }

  test('explicit session streams video and HEAD with exact type and length', () async {
    final session = await start();
    final get = await request(session.mediaUri);
    expect(get.response.statusCode, 200);
    expect(get.response.contentLength, 10);
    expect(get.response.headers.contentType?.mimeType, 'video/mp4');
    expect(utf8.decode(get.bytes), '0123456789');
    final head = await request(session.mediaUri, method: 'HEAD');
    expect(head.response.statusCode, 200);
    expect(head.response.contentLength, 10);
    expect(head.bytes, isEmpty);
    expect(session.subtitleUri, isNull);
  });

  test('subtitle shares an unguessable independent session token', () async {
    final sub = await File('${root.path}/captions.vtt').writeAsString('WEBVTT\n');
    final first = await start(subtitle: sub);
    final second = await start();
    expect(first.mediaUri.pathSegments.first, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(first.subtitleUri!.pathSegments.first, first.mediaUri.pathSegments.first);
    expect(second.mediaUri.pathSegments.first, isNot(first.mediaUri.pathSegments.first));
    final response = await request(first.subtitleUri!);
    expect(response.response.headers.contentType?.mimeType, 'text/vtt');
    expect(utf8.decode(response.bytes), 'WEBVTT\n');
  });

  test('range GET and HEAD expose exact selected bytes and headers', () async {
    final session = await start();
    for (final value in <(String,String,String)>[
      ('bytes=2-5','2345','bytes 2-5/10'),
      ('bytes=7-','789','bytes 7-9/10'),
      ('bytes=-3','789','bytes 7-9/10'),
      ('bytes=8-99','89','bytes 8-9/10'),
    ]) {
      final response = await request(session.mediaUri, range:value.$1);
      expect(response.response.statusCode,206);
      expect(utf8.decode(response.bytes),value.$2);
      expect(response.response.headers.value('content-range'),value.$3);
      expect(response.response.headers.value('accept-ranges'),'bytes');
    }
    final head = await request(session.mediaUri,method:'HEAD',range:'bytes=2-5');
    expect(head.response.statusCode,206);
    expect(head.response.contentLength,4);
    expect(head.bytes,isEmpty);
  });

  test('invalid and unsupported multiple ranges return 416, not full video', () async {
    final session = await start();
    for(final range in ['bytes=100-','bytes=6-3','bytes=-0','items=0-1','bytes=0-1,4-5']) {
      final response=await request(session.mediaUri,range:range);
      expect(response.response.statusCode,416,reason:range);
      expect(response.response.headers.value('content-range'),'bytes */10');
      expect(response.bytes,isEmpty);
    }
  });

  test('manifest extra resources are explicitly registered, with no directory access', () async {
    final segment=await File('${root.path}/segment.ts').writeAsString('segment');
    final session=await start(extras:{'nested/part.ts':segment});
    expect(utf8.decode((await request(session.mediaUri.resolve('nested/part.ts'))).bytes),'segment');
    expect((await request(session.mediaUri.resolve('segment.ts'))).response.statusCode,404);
    expect((await request(session.mediaUri.replace(path:'/wrong/media.mp4'))).response.statusCode,404);
    expect((await request(session.mediaUri.resolve('../private'))).response.statusCode,404);
    await expectLater(start(extras:{'../private':segment}),throwsArgumentError);
    await expectLater(start(extras:{'media.mp4':segment}),throwsArgumentError);
  });

  test('registered paths cannot follow a symlink replaced after session creation', () async {
    final secret=await File('${root.path}/private.mp4').writeAsString('secret');
    final link=await Link('${root.path}/selected.mp4').create(video.path);
    final session=await start(file:File(link.path));
    expect((await request(session.mediaUri)).response.statusCode,200);
    await link.delete(); await link.create(secret.path);
    expect((await request(session.mediaUri)).response.statusCode,404);
  });

  test('methods are restricted and Cast preflight exposes only registered resources', () async {
    final session=await start();
    final post=await request(session.mediaUri,method:'POST');
    expect(post.response.statusCode,405);
    final options=await request(session.mediaUri,method:'OPTIONS');
    expect(options.response.statusCode,204);
    expect(options.response.headers.value('access-control-allow-origin'),'*');
    expect(options.bytes,isEmpty);
  });

  test('close is idempotent and listening socket no longer accepts requests', () async {
    final session = await start();
    await session.close();
    await session.close();
    expect(() => request(session.mediaUri), throwsA(isA<SocketException>()));
  });
}
