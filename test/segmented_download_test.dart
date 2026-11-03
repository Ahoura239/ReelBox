import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/segmented_download.dart';

void main() {
  late Directory root;
  late HttpServer server;
  late String origin;
  final requests = <String>[];
  final fixtures = <String,String>{};
  final failures = <String>{};
  final redirects = <String, String>{};
  final responseCodes = <String, int>{};
  final encodings = <String>[];
  var incorrectRange = false;
  var active = 0, peak = 0;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('reelbox-offline-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://${server.address.address}:${server.port}';
    requests.clear(); fixtures.clear(); failures.clear(); redirects.clear(); active = 0; peak = 0;
    responseCodes.clear(); encodings.clear(); incorrectRange = false;
    server.listen((request) async {
      requests.add('${request.uri.path}:${request.headers.value('range') ?? ''}');
      encodings.add('${request.uri.path}:${request.headers.value('accept-encoding') ?? ''}');
      active++; if (active > peak) peak = active;
      try {
        final path = request.uri.path;
        request.response.statusCode = responseCodes[path] ?? 200;
        if (failures.contains(path)) {
          request.response.statusCode = 403;
        } else if (redirects.containsKey(path)) {
          request.response.statusCode = responseCodes[path] ?? 302;
          request.response.headers.set(HttpHeaders.locationHeader, redirects[path]!);
        } else if (fixtures.containsKey(path)) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          final bytes = utf8.encode(fixtures[path]!);
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
        } else if (path == '/master.m3u8') {
          request.response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\nvideo/list.m3u8\n');
        } else if (path == '/video/list.m3u8') {
          request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI="../blob",BYTERANGE="4@0"\n#EXTINF:2,\n#EXT-X-BYTERANGE:4@4\n../blob\n#EXTINF:2,\n#EXT-X-BYTERANGE:4\n../blob\n#EXT-X-ENDLIST\n');
        } else if (path == '/blob') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          final range = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers.value('range') ?? '')!;
          final start = int.parse(range[1]!), end = int.parse(range[2]!);
          request.response.statusCode = 206;
          request.response.headers.set('content-range', incorrectRange ? 'bytes 0-0/12' : 'bytes $start-$end/12');
          request.response.contentLength = end - start + 1;
          request.response.add(utf8.encode('INITAAAABBBB').sublist(start, end + 1));
        } else {
          request.response.statusCode = 404;
        }
      } finally {
        await request.response.close(); active--;
      }
    });
  });
  tearDown(() async { await server.close(force: true); await root.delete(recursive: true); });

  test('HLS master downloads bounded parallel ranges and publishes fully local validated package', () async {
    final engine = SegmentedDownload(root: root, parallel: 2);
    await engine.prepare(id: 'hls', url: '$origin/master.m3u8');
    final result = await engine.run('hls');
    expect(result.status, 'complete');
    expect(await engine.validate('hls'), isTrue);
    expect(peak, 2);
    expect(requests, containsAll(['/blob:bytes=0-3', '/blob:bytes=4-7', '/blob:bytes=8-11']));
    final resources = result.resources;
    expect(resources.length, 3);
    for (final resource in resources) {
      final bytes = await File('${result.directory}/${resource.filename}').readAsBytes();
      expect(bytes.length, 4);
      expect(sha256.convert(bytes).toString(), resource.digest);
    }
    final playlists = await Directory(result.directory).list().where((f) => f.path.endsWith('.m3u8')).toList();
    expect(playlists.length, 2);
    for (final playlist in playlists) {
      final text = await File(playlist.path).readAsString();
      expect(text, isNot(contains(origin)));
      expect(text, isNot(contains('BYTERANGE')));
    }
    final zip = ZipDecoder().decodeBytes(await File(await engine.export('hls')).readAsBytes());
    expect(zip.files.map((f)=>f.name).toSet(), {...result.manifests.keys,...resources.map((r)=>r.filename)});
    expect(zip.files.any((f)=>f.name=='package.json'),false);
    for(final r in resources) {
      expect(sha256.convert(zip.findFile(r.filename)!.content).toString(),r.digest);
    }
    await File('${result.directory}/${resources.last.filename}').writeAsString('BAD!');
    expect(await engine.validate('hls'), isFalse);
  });
  test('redirected HLS master and children use effective URIs for all resources', () async {
    redirects.addAll({
      '/entry/master.m3u8': '/media/master.m3u8',
      '/media/video.m3u8': 'video/list.m3u8',
      '/media/audio.m3u8': 'audio/list.m3u8',
      '/media/subs.m3u8': 'subs/list.m3u8',
    });
    fixtures['/media/master.m3u8'] = '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Audio",DEFAULT=YES,URI="audio.m3u8"\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="sub",NAME="Subs",DEFAULT=YES,URI="subs.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=100,AUDIO="aud",SUBTITLES="sub"\nvideo.m3u8\n';
    fixtures['/media/video/list.m3u8'] = '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key",IV=0x00000000000000000000000000000001\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:1,\na.ts\n#EXT-X-ENDLIST\n';
    fixtures['/media/audio/list.m3u8'] = '#EXTM3U\n#EXTINF:1,\na.aac\n#EXT-X-ENDLIST\n';
    fixtures['/media/subs/list.m3u8'] = '#EXTM3U\n#EXTINF:1,\na.vtt\n#EXT-X-ENDLIST\n';
    fixtures.addAll({
      '/media/video/key': '0123456789abcdef',
      '/media/video/init.mp4': 'INIT', '/media/video/a.ts': 'VIDEO',
      '/media/audio/a.aac': 'AUDIO', '/media/subs/a.vtt': 'WEBVTT\n',
    });
    final engine = SegmentedDownload(root: root);
    final planned = await engine.prepare(id: 'redirect_hls', url: '$origin/entry/master.m3u8');
    expect(planned.resources.map((r) => Uri.parse(r.url).path).toSet(), {
      '/media/video/key', '/media/video/init.mp4', '/media/video/a.ts',
      '/media/audio/a.aac', '/media/subs/a.vtt',
    });
    final result = await engine.run(planned.id);
    expect(result.status, 'complete', reason: result.error);
    expect(await engine.validate(planned.id), isTrue);
    expect(requests.any((r) => r.startsWith('/entry/') && r != '/entry/master.m3u8:'), isFalse);
  });

  test('resource redirects validate each hop before fetching excluded targets', () async {
    fixtures['/vod.m3u8'] = '#EXTM3U\n#EXTINF:1,\na.ts\n#EXT-X-ENDLIST\n';
    redirects.addAll({'/a.ts': '/allowed-hop', '/allowed-hop': '/moviebox/support/blocked.ts'});
    fixtures['/moviebox/support/blocked.ts'] = 'MUST NOT FETCH';
    final engine = SegmentedDownload(root: root);
    await engine.prepare(id: 'blocked_resource', url: '$origin/vod.m3u8');
    final result = await engine.run('blocked_resource');
    expect(result.status, 'failed');
    expect(result.error, contains('authorized'));
    expect(requests, ['/vod.m3u8:', '/a.ts:', '/allowed-hop:']);
    expect(await File(result.path).exists(), isFalse);
    expect(await engine.validate(result.id), isFalse);
  });

  test('redirected extensionless DASH resolves nested BaseURLs at the effective URI', () async {
    redirects['/entry/manifest'] = '/media/movie/manifest';
    fixtures['/media/movie/manifest'] = '<MPD type="static"><BaseURL>parts/</BaseURL><Period><BaseURL>period/</BaseURL><AdaptationSet><BaseURL>video/</BaseURL><Representation><BaseURL>main/</BaseURL><SegmentList duration="1"><Initialization sourceURL="init.mp4"/><SegmentURL media="a.m4s"/></SegmentList></Representation></AdaptationSet></Period></MPD>';
    fixtures.addAll({
      '/media/movie/parts/period/video/main/init.mp4': 'INIT',
      '/media/movie/parts/period/video/main/a.m4s': 'VIDEO',
    });
    final engine = SegmentedDownload(root: root);
    final planned = await engine.prepare(id: 'redirect_dash', url: '$origin/entry/manifest', type: 'mpd');
    expect(planned.manifest, 'offline.mpd');
    expect(planned.resources.map((r) => Uri.parse(r.url).path).toSet(), {
      '/media/movie/parts/period/video/main/init.mp4',
      '/media/movie/parts/period/video/main/a.m4s',
    });
    final result = await engine.run(planned.id);
    expect(result.status, 'complete', reason: result.error);
    expect(await engine.validate(result.id), isTrue);
    expect(await File(result.path).readAsString(), isNot(contains('BaseURL')));
  });

  for (final code in [301, 302, 303, 307, 308]) {
    test('manifest HTTP $code resolves relative Location against each hop', () async {
      redirects.addAll({'/entry/start': 'next', '/entry/next': '../media/vod'});
      responseCodes.addAll({'/entry/start': code, '/entry/next': code});
      fixtures['/media/vod'] = '#EXTM3U\n#EXTINF:1,\na.ts\n#EXT-X-ENDLIST\n';
      fixtures['/media/a.ts'] = 'MEDIA';
      final engine = SegmentedDownload(root: root);
      await engine.prepare(id: 'status_$code', url: '$origin/entry/start');
      final result = await engine.run('status_$code');
      expect(result.status, 'complete', reason: result.error);
      expect(requests, ['/entry/start:', '/entry/next:', '/media/vod:', '/media/a.ts:']);
    });
  }

  test('manifest redirects validate intermediate targets before requesting them', () async {
    redirects.addAll({'/entry': '/allowed', '/allowed': '/moviebox/news/manifest'});
    fixtures['/moviebox/news/manifest'] = '#EXTM3U\n#EXTINF:1,\na.ts\n#EXT-X-ENDLIST\n';
    final engine = SegmentedDownload(root: root);
    await expectLater(engine.prepare(id: 'denied_manifest', url: '$origin/entry'), throwsUnsupportedError);
    expect(requests, ['/entry:', '/allowed:']);
    expect(await Directory('${root.path}/denied_manifest').exists(), isFalse);
  });

  for (final target in ['file:///private/media', 'http://user:secret@127.0.0.1/media', '/moviebox/%73upport/media']) {
    test('manifest redirects reject unauthorized target $target', () async {
      redirects['/entry'] = target;
      final engine = SegmentedDownload(root: root);
      await expectLater(engine.prepare(id: 'unauthorized', url: '$origin/entry'), throwsUnsupportedError);
      expect(requests, ['/entry:']);
    });
  }

  test('manifest and resource redirect loops stop after five hops', () async {
    redirects['/loop'] = '/loop';
    final engine = SegmentedDownload(root: root);
    await expectLater(engine.prepare(id: 'loop_manifest', url: '$origin/loop'),
        throwsA(isA<HttpException>().having((e) => e.message, 'message', contains('Too many'))));
    expect(requests, List.filled(6, '/loop:'));
    expect(await Directory('${root.path}/loop_manifest').exists(), isFalse);
    requests.clear();
    fixtures['/vod'] = '#EXTM3U\n#EXTINF:1,\nloop\n#EXT-X-ENDLIST\n';
    await engine.prepare(id: 'loop_resource', url: '$origin/vod');
    final result = await engine.run('loop_resource');
    expect(result.status, 'failed');
    expect(result.error, contains('Too many'));
    expect(requests, ['/vod:', ...List.filled(6, '/loop:')]);
    expect(await File(result.path).exists(), isFalse);
  });

  test('manifest and resource redirects without Location fail closed', () async {
    fixtures['/missing'] = '';
    responseCodes['/missing'] = 302;
    final engine = SegmentedDownload(root: root);
    await expectLater(engine.prepare(id: 'missing_manifest', url: '$origin/missing'),
        throwsA(isA<HttpException>().having((e) => e.message, 'message', contains('Location'))));
    fixtures['/vod'] = '#EXTM3U\n#EXTINF:1,\nmissing\n#EXT-X-ENDLIST\n';
    await engine.prepare(id: 'missing_resource', url: '$origin/vod');
    final result = await engine.run('missing_resource');
    expect(result.status, 'failed');
    expect(result.error, contains('Location'));
    expect(requests, ['/missing:', '/vod:', '/missing:']);
  });

  test('resource redirects preserve Range and identity headers on every hop', () async {
    fixtures['/vod'] = '#EXTM3U\n#EXTINF:1,\n#EXT-X-BYTERANGE:4@4\nrange\n#EXT-X-ENDLIST\n';
    redirects.addAll({'/range': '/range-hop', '/range-hop': '/blob'});
    final engine = SegmentedDownload(root: root);
    await engine.prepare(id: 'redirect_range', url: '$origin/vod');
    final result = await engine.run('redirect_range');
    expect(result.status, 'complete', reason: result.error);
    expect(requests, ['/vod:', '/range:bytes=4-7', '/range-hop:bytes=4-7', '/blob:bytes=4-7']);
    expect(encodings.skip(1), ['/range:identity', '/range-hop:identity', '/blob:identity']);
    expect(await File('${result.directory}/${result.resources.single.filename}').readAsString(), 'AAAA');
    expect(await engine.validate(result.id), isTrue);
  });

  for (final mode in ['ignored', 'incorrect']) {
    test('redirected resource still rejects $mode byte range responses', () async {
      fixtures['/vod'] = '#EXTM3U\n#EXTINF:1,\n#EXT-X-BYTERANGE:4@4\nrange\n#EXT-X-ENDLIST\n';
      redirects['/range'] = mode == 'ignored' ? '/whole' : '/blob';
      fixtures['/whole'] = 'INITAAAABBBB';
      incorrectRange = mode == 'incorrect';
      final engine = SegmentedDownload(root: root);
      await engine.prepare(id: 'bad_range', url: '$origin/vod');
      final result = await engine.run('bad_range');
      expect(result.status, 'failed');
      expect(result.error, contains(mode == 'ignored' ? 'Resource HTTP 200' : 'Incorrect Content-Range'));
      expect(await File(result.path).exists(), isFalse);
    });
  }

  for (final code in [401, 403]) {
    test('redirected manifests and resources retain HTTP $code denials', () async {
      redirects['/entry'] = '/denied';
      fixtures['/denied'] = 'Access denied';
      responseCodes['/denied'] = code;
      final engine = SegmentedDownload(root: root);
      await expectLater(engine.prepare(id: 'denied_manifest', url: '$origin/entry'),
          throwsA(isA<HttpException>().having((e) => e.message, 'message', 'Manifest HTTP $code')));
      fixtures['/vod'] = '#EXTM3U\n#EXTINF:1,\nentry\n#EXT-X-ENDLIST\n';
      await engine.prepare(id: 'denied_resource', url: '$origin/vod');
      final result = await engine.run('denied_resource');
      expect(result.status, 'failed');
      expect(result.error, contains('Resource HTTP $code'));
      expect(await File(result.path).exists(), isFalse);
      expect(requests, ['/entry:', '/denied:', '/vod:', '/entry:', '/denied:']);
    });
  }

  test('HLS refuses encrypted init maps without explicit IV before creating a package', () async {
    fixtures['/encrypted.m3u8'] = '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:2,\na.ts\n#EXT-X-ENDLIST\n';
    final engine = SegmentedDownload(root: root);
    await expectLater(engine.prepare(id:'unsafe',url:'$origin/encrypted.m3u8'),throwsUnsupportedError);
    expect(await Directory('${root.path}/unsafe').exists(),isFalse);
  });
  test('cancel/restart reuses only hash-validated complete segments and never publishes incomplete manifests', () async {
    fixtures['/vod.m3u8']='#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\na.ts\n#EXTINF:2,\nb.ts\n#EXTINF:2,\nc.ts\n#EXT-X-ENDLIST\n';
    fixtures.addAll({'/a.ts':'AAAA','/b.ts':'BBBB','/c.ts':'CCCC'});
    final engine=SegmentedDownload(root:root,parallel:1);
    await engine.prepare(id:'resume',url:'$origin/vod.m3u8',metadata:{'notifications':false});
    var stopping=false;
    final run=engine.run('resume',onProgress:(p) {
      if(p.receivedBytes>=4 && !stopping) { stopping=true; engine.stop('resume'); }
    });
    final paused=await run;
    expect(paused.status,'paused');
    expect(await File(paused.path).exists(),isFalse);
    expect(await engine.validate('resume'),isFalse);
    final stateFile=File('${paused.directory}/package.json');
    final saved=jsonDecode(await stateFile.readAsString()) as Map<String,dynamic>;
    saved['status']='running'; // OS termination before a status checkpoint.
    await stateFile.writeAsString(jsonEncode(saved));
    final restarted=SegmentedDownload(root:root,parallel:2);
    final recovered=(await restarted.recover()).single;
    expect(recovered.status,'paused');
    expect(recovered.metadata['notifications'],false);
    requests.clear();
    final completed=await restarted.run('resume');
    expect(completed.status,'complete');
    expect(requests, isNot(contains('/a.ts:')));
    expect(await restarted.validate('resume'),isTrue);
    await File('${completed.directory}/${completed.resources.first.filename}').writeAsString('EVIL');
    final damaged=(await SegmentedDownload(root:root).recover()).single;
    expect(damaged.status,'failed');
    requests.clear();
    final repaired=await restarted.run('resume');
    expect(repaired.status,'complete');
    expect(requests,['/a.ts:']);
    expect(await restarted.validate('resume'),isTrue);
  });
  test('denied resource is failed, retains validated progress, and retry repairs it', () async {
    fixtures['/vod.m3u8']='#EXTM3U\n#EXTINF:1,\na.ts\n#EXTINF:1,\nb.ts\n#EXT-X-ENDLIST\n';
    fixtures.addAll({'/a.ts':'AAAA','/b.ts':'BBBB'});
    failures.add('/b.ts');
    final engine=SegmentedDownload(root:root,parallel:1);
    await engine.prepare(id:'denied',url:'$origin/vod.m3u8');
    final failed=await engine.run('denied');
    expect(failed.status,'failed');
    expect(failed.receivedBytes,4);
    expect(await File(failed.path).exists(),isFalse);
    failures.clear(); requests.clear();
    expect((await SegmentedDownload(root:root).run('denied')).status,'complete');
    expect(requests,['/b.ts:']);
  });
  test('AES-128 identity keys and separate default audio are packaged locally', () async {
    fixtures['/audio-master.m3u8']='#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",DEFAULT=YES,URI="audio.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=500,AUDIO="aud"\nvideo.m3u8\n';
    fixtures['/audio.m3u8']='#EXTM3U\n#EXTINF:1,\na.aac\n#EXT-X-ENDLIST\n';
    fixtures['/video.m3u8']='#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key",IV=0x00000000000000000000000000000001\n#EXTINF:1,\nv.ts\n#EXT-X-ENDLIST\n';
    fixtures.addAll({'/a.aac':'AUDIO','/v.ts':'ENCRYPTED-MEDIA','/key':'0123456789abcdef'});
    final engine=SegmentedDownload(root:root);
    await engine.prepare(id:'audio',url:'$origin/audio-master.m3u8');
    final p=await engine.run('audio');
    expect(p.status,'complete'); expect(p.resources.length,3);
    expect(p.resources.singleWhere((r)=>r.key).bytes,16);
    expect(await engine.validate('audio'),isTrue);
  });
  test('reject DRM, live manifests, dynamic DASH and unbounded timelines', () async {
    final engine=SegmentedDownload(root:root);
    final cases=<String,String>{
      'live':'#EXTM3U\n#EXTINF:1,\na.ts\n',
      'drm':'#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,KEYFORMAT="com.apple.streamingkeydelivery",URI="skd://protected"\n#EXTINF:1,\na.ts\n#EXT-X-ENDLIST\n',
      'dashdrm':'<MPD><Period><AdaptationSet><ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011"/><Representation/></AdaptationSet></Period></MPD>',
      'dynamic':'<MPD type="dynamic"><Period/></MPD>',
      'unbounded':'<MPD><Period><AdaptationSet><Representation><SegmentTemplate media="a-\$Time\$.m4s"><SegmentTimeline><S d="2" r="-1"/></SegmentTimeline></SegmentTemplate></Representation></AdaptationSet></Period></MPD>',
    };
    for(final entry in cases.entries) {
      fixtures['/${entry.key}']=entry.value;
      await expectLater(engine.prepare(id:entry.key,url:'$origin/${entry.key}'),throwsUnsupportedError,reason:entry.key);
      expect(await Directory('${root.path}/${entry.key}').exists(),false);
    }
  });
  test('clear static DASH template packages audio and video with local SegmentLists', () async {
    fixtures['/movie.mpd'] = '''<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT4S"><BaseURL>media/</BaseURL><Period><AdaptationSet mimeType="video/mp4"><SegmentTemplate timescale="1" duration="2" startNumber="5" initialization="\$RepresentationID\$/init.mp4" media="\$RepresentationID\$/\$Number%03d\$.m4s"/><Representation id="video" bandwidth="800"/></AdaptationSet><AdaptationSet mimeType="audio/mp4"><Representation id="audio" bandwidth="100"><SegmentList timescale="1" duration="2"><Initialization sourceURL="audio/init.mp4"/><SegmentURL media="audio/1.m4s"/><SegmentURL media="audio/2.m4s"/></SegmentList></Representation></AdaptationSet></Period></MPD>''';
    for (final path in ['video/init.mp4','video/005.m4s','video/006.m4s','audio/init.mp4','audio/1.m4s','audio/2.m4s']) {
      fixtures['/media/$path'] = 'BYTES:$path';
    }
    final engine = SegmentedDownload(root: root, parallel: 3);
    await engine.prepare(id: 'dash', url: '$origin/movie.mpd');
    final result = await engine.run('dash');
    expect(result.status, 'complete');
    expect(result.resources.length, 6);
    expect(await engine.validate('dash'), isTrue);
    final manifest = await File(result.path).readAsString();
    expect(manifest, contains('SegmentList'));
    expect(manifest, isNot(contains('SegmentTemplate')));
    expect(manifest, isNot(contains('BaseURL')));
    expect(manifest, isNot(contains(origin)));
    for (final r in result.resources) {
      expect(await File('${result.directory}/${r.filename}').readAsString(), fixtures[Uri.parse(r.url).path]);
      expect(manifest, contains(r.filename));
    }
  });
}
