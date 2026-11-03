import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';

class StubAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  StubAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (body != null) {
      bodies.add(utf8.decode(await body.expand((chunk) => chunk).toList()));
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(dynamic data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

void main() {
  test(
    'observed search IDs take precedence over unrelated posted_id values',
    () {
      final api = ApiService();
      final raw = jsonDecode(
        File('test/fixtures/search.json').readAsStringSync(),
      );
      final titles = api.decodeTitles(raw);
      expect(titles.map((title) => title.id).toList(), [32789, 18602]);
      expect(titles.first.year, 2026);
      expect(titles.first.imdb, 10);
      expect(titles.first.raw['posted_id'], '2324949');
      expect(titles.first.image, raw[0]['image']);
      for (final key in ['posters', 'data', 'result', 'items']) {
        expect(api.decodeTitles({key: raw}).map((title) => title.id), [
          32789,
          18602,
        ]);
      }
      expect(api.decodeTitles(null), isEmpty);
      expect(
        api.decodeTitles([
          null,
          12,
          {},
          {'id': '1', 'title': ''},
        ]),
        isEmpty,
      );
      expect(
        () => api.decodeTitles({'unexpected': 'shape'}),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test('search, recommendation, trending and actors use observed queries; removed public lists never request', () async {
    final raw = jsonDecode(
      File('test/fixtures/search.json').readAsStringSync(),
    );
    final adapter = StubAdapter((request) {
      if (request.uri.queryParameters['action'] == 'search-trand') {
        return jsonBody([
          'Avatar',
          {'title': 'Dune'},
          {'q': 'Lost'},
          null,
          {},
        ]);
      }
      return jsonBody(raw);
    });
    final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
    expect((await api.search('A & ب', page: 2)).first.id, 32789);
    await api.search('Avatar', english: true);
    await api.recommended(3, page: 2);
    await api.bestRandom();
    await api.bestRandom(byYear: true, page: 3);
    expect(await api.trending(), ['Avatar', 'Dune', 'Lost']);
    await api.actors(page: 2);
    await api.actors(search: ' Tom & ب ', page: 3);
    expect(await api.playlists(page: 2), isEmpty);
    expect(await api.playlistItems(3328, page: 3), isEmpty);
    expect(adapter.requests.map((r) => r.uri.path).toList(), [
      '/api-user/newapi/like.php',
      '/api-user/newapi/like.php',
      '/api-user/newapi/filter.php',
      '/api-user/newapi/like.php',
      '/api-user/newapi/like.php',
      '/api-user/newapi/like.php',
      '/api-user/newapi/like.php',
      '/api-user/filmahang/star.php',
    ]);
    expect(adapter.requests.map((r) => r.uri.queryParameters).toList(), [
      {'action': 'search-movie', 'q': 'A & ب', 'pageno': '2'},
      {'action': 'search-movie-en', 'q': 'Avatar', 'pageno': '1'},
      {'action': 'pishnahad', 'garid': '3', 'pageno': '2'},
      {'action': 'best-rand-top', 'pageno': '1'},
      {'action': 'best-rand-year', 'pageno': '3'},
      {'action': 'search-trand', 'pageno': '1'},
      {'action': 'all-actor', 'pageno': '2'},
      {
        'key': const String.fromEnvironment('REELBOX_ACTOR_KEY'),
        'action': 'starsearch',
        'q': 'Tom & ب',
        'pageno': '3',
      },
    ]);
    expect(
      adapter.requests.every((request) => request.method == 'GET'),
      isTrue,
    );
    await expectLater(
      api.playlists(mine: true, userId: '1'),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, hasLength(8));
  });
  test('real curated parallel arrays flatten and rewrite allowlisted legacy links safely', () async {
    final raw = jsonDecode(
      File('test/fixtures/curated.json').readAsStringSync(),
    );
    final adapter = StubAdapter(
      (request) => request.uri.path.endsWith('filter.php')
          ? jsonBody(
              jsonDecode(File('test/fixtures/search.json').readAsStringSync()),
            )
          : jsonBody(raw),
    );
    final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
    final links = await api.curatedLinks();
    expect(links.single['title'], 'ترسناک');
    expect(
      links.single['link'],
      'https://ninwinios.info/api-user/newapi/filter.php?action=pishnahad&garid=1&pageno=',
    );
    await api.curatedLinks(best: true);
    final titles = await api.curatedContent(
      links.single['link'] as String,
      page: 3,
    );
    expect(titles.first.id, 32789);
    expect(adapter.requests[0].uri.path, '/api-user/newapi/pishnahad.php');
    expect(adapter.requests[1].uri.path, '/api-user/newapi/bartar.php');
    expect(adapter.requests[2].uri.queryParameters['pageno'], '3');
    expect(adapter.requests[2].uri.queryParametersAll['pageno'], ['3']);
    await expectLater(
      api.curatedContent('https://evil.example/api-user/newapi/filter.php'),
      throwsA(isA<ApiException>()),
    );
  });
  test(
    'public catalog endpoints preserve original routes and zero-based pages',
    () async {
      final movie = jsonDecode(
        File('test/fixtures/movie.json').readAsStringSync(),
      );
      final season = jsonDecode(
        File('test/fixtures/season.json').readAsStringSync(),
      );
      final adapter = StubAdapter((request) {
        final path = request.uri.path;
        if (path.contains('/first/')) {
          return jsonBody({
            'posters': [movie],
            'genres': [],
          });
        }
        if (path.contains('/all/')) {
          return jsonBody([
            {'id': 3, 'title': 'انیمیشن + انیمه'},
          ]);
        }
        if (path.contains('/season/')) return jsonBody([season]);
        if (path.contains('/movie/by/35721/')) return jsonBody(movie);
        if (path.contains('/channel/by/17/')) {
          return jsonBody({...movie, 'id': 17, 'type': 'channel'});
        }
        return jsonBody([movie]);
      });
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      expect((await api.home())['posters'][0]['id'], 35721);
      expect((await api.genres()).single.id, 3);
      expect((await api.countries()).single.id, 3);
      expect(await api.categories(), isEmpty);
      expect((await api.catalog()).single.id, 35721);
      await api.catalog(kind: 'serie', genre: 3, order: 'imdb', page: 2);
      await api.catalog(
        kind: 'mixed',
        genre: 2,
        country: 9,
        order: 'year',
        page: 1,
      );
      await api.catalog(country: 9);
      expect(await api.channels(category: 17, country: 1, page: 2), isEmpty);
      expect((await api.poster(35721)).id, 35721);
      await expectLater(api.channel(17), throwsA(isA<ApiException>()));
      expect((await api.seasons(1003)).single.episodes.first.id, 72819);
      await api.actorTitles(582);
      await api.roles(35721);
      await api.subtitles('movie', 35721);
      await api.subtitles('episode', 72819);
      await api.comments(35721);
      const k = ApiService.sharedKey;
      expect(adapter.requests.map((r) => r.uri.path).toList(), [
        '/api/first/$k/',
        '/api/genre/all/$k/',
        '/api/country/all/$k/',
        '/api/movie/by/filtres/0/created/0/$k/',
        '/api/serie/by/filtres/3/imdb/2/$k/',
        '/api/poster/by/filtres/2/9/year/1/$k/',
        '/api/poster/by/filtres/0/9/created/0/$k/',
        '/api/movie/by/35721/$k/',
        '/api/season/by/serie/1003/$k/',
        '/api/movie/by/actor/582/$k/',
        '/api/role/by/poster/35721/$k/',
        '/api/subtitles/by/movie/35721/$k/',
        '/api/subtitles/by/episode/72819/$k/',
        '/api/comments/by/poster/35721/$k/',
      ]);
    },
  );
  test(
    'invalid catalog kinds and subtitle kinds cannot inject routes',
    () async {
      final adapter = StubAdapter((_) => jsonBody([]));
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      await expectLater(
        api.catalog(kind: '../user'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.subtitles('../user', 1),
        throwsA(isA<ApiException>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'rejects untrusted, insecure and ambiguous routes before transport',
    () async {
      final adapter = StubAdapter((_) => jsonBody([]));
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      for (final path in [
        'https://attacker.example/api/',
        'http://ninwinios.info/api/first/',
        '//attacker.example/api/',
        'https://ninwinios.info@attacker.example/api/',
        'https://user:secret@ninwinios.info/api/',
        'https://ninwinios.info:444/api/',
        '../private',
        '/api/../private',
        '/api/%2e%2e/private',
        r'\evil\api',
        'genre/all/#secret',
        'file:///api/first',
      ]) {
        await expectLater(
          api.get(path),
          throwsA(isA<ApiException>()),
          reason: path,
        );
      }
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'rewrites only allowlisted legacy public links to HTTPS current host',
    () async {
      final adapter = StubAdapter((_) => jsonBody([]));
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      await api.get(
        'http://simbaapp.info/api-user/newapi/filter.php?action=best&x=a%2Fb',
      );
      expect(
        adapter.requests.single.uri.toString(),
        'https://ninwinios.info/api-user/newapi/filter.php?action=best&x=a%2Fb',
      );
    },
  );
  test(
    'base updates are atomic, allow HTTPS service and local HTTP tests only',
    () async {
      final api = ApiService();
      for (final url in [
        'http://ninwinios.info/api/',
        'https://attacker.example/api/',
        'https://user:secret@ninwinios.info/api/',
        'https://ninwinios.info/other/',
      ]) {
        await expectLater(api.setBaseUrl(url), throwsA(isA<ApiException>()));
        expect(api.baseUrl, ApiService.defaultBaseUrl);
      }
      await api.setBaseUrl('http://127.0.0.1:8080/api');
      expect(api.baseUrl, 'http://127.0.0.1:8080/api/');
      expect(
        () => ApiService(baseUrl: 'http://evil.example/api/'),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'generic POST is form encoded and never follows credential redirects',
    () async {
      final adapter = StubAdapter((request) {
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        return ResponseBody.fromString(
          '',
          307,
          headers: {
            'location': ['https://evil.example/collect'],
          },
        );
      });
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      try {
        await api.post('test-only', {
          'password': 'never-log-me',
          'comment': 'a & ب',
        });
        fail('Redirect must not succeed');
      } on ApiException catch (error) {
        expect(error.statusCode, 307);
        expect(error.toString(), isNot(contains('never-log-me')));
        expect(error.toString(), isNot(contains('test-only')));
      }
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.contentType,
        Headers.formUrlEncodedContentType,
      );
      expect(Uri.splitQueryString(adapter.bodies.single), {
        'password': 'never-log-me',
        'comment': 'a & ب',
      });
    },
  );
  test(
    'discovery upgrades advertised HTTP but rejects unsigned unknown hosts',
    () async {
      for (final candidate in [
        'http://ninwinios.info/api/',
        'https://attacker.example/api/',
      ]) {
        final adapter = StubAdapter((request) {
          if (request.uri.host == 'ninnies-server.info') {
            return ResponseBody.fromString(candidate, 200);
          }
          return jsonBody([
            {'id': 1, 'title': 'ترسناک'},
          ]);
        });
        final dio = Dio(BaseOptions(headers: {'Authorization': 'secret'}))
          ..httpClientAdapter = adapter;
        final api = ApiService(dio: dio);
        await api.initialize();
        expect(api.baseUrl, ApiService.defaultBaseUrl);
        expect(
          adapter.requests.first.uri.toString(),
          'https://ninnies-server.info/api-user/newapi/config-server186.txt',
        );
        expect(
          adapter.requests.every(
            (request) => !request.headers.containsKey('Authorization'),
          ),
          isTrue,
        );
        expect(
          adapter.requests.any(
            (request) => request.uri.host == 'attacker.example',
          ),
          isFalse,
        );
      }
    },
  );
  test(
    'HTML, malformed JSON, timeout and HTTP denials produce safe errors',
    () async {
      for (final status in [200, 401, 403, 500]) {
        final adapter = StubAdapter(
          (_) =>
              ResponseBody.fromString('<html>private details</html>', status),
        );
        final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
        await expectLater(
          api.get('private/password-secret'),
          throwsA(
            isA<ApiException>().having(
              (error) => error.toString(),
              'sanitized message',
              isNot(contains('password-secret')),
            ),
          ),
        );
      }
      final adapter = StubAdapter(
        (request) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: request,
        ),
      );
      await expectLater(
        ApiService(dio: Dio()..httpClientAdapter = adapter).get('secret'),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'HTTPS relative route uses timeouts, correct shared key and JSON decoding',
    () async {
      final adapter = StubAdapter(
        (_) => jsonBody([
          {'id': 1, 'title': 'ترسناک'},
        ]),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final api = ApiService(dio: dio);
      await api.initialize(discover: false);
      final result = await api.get('genre/all/${ApiService.sharedKey}/');
      expect(result[0]['id'], 1);
      expect(
        ApiService.sharedKey,
        const String.fromEnvironment('REELBOX_API_KEY'),
      );
      expect(api.baseUrl, 'https://ninwinios.info/api/');
      expect(api.hostRoot, 'https://ninwinios.info');
      final request = adapter.requests.single;
      expect(
        request.uri.toString(),
        '${api.baseUrl}genre/all/${ApiService.sharedKey}/',
      );
      expect(request.connectTimeout, isNotNull);
      expect(request.receiveTimeout, isNotNull);
      expect(request.sendTimeout, isNotNull);
      expect(request.followRedirects, isFalse);
    },
  );
}
