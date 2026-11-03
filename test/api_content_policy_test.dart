import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';

import 'api_service_test.dart' as fixtures;

void main() {
  test(
    'all title decoders reject channels and promotional catalog entries',
    () {
      final api = ApiService();
      expect(
        api
            .decodeTitles([
              {'id': 1, 'title': 'A real movie', 'type': 'movie'},
              {'id': 2, 'title': 'نورتون', 'type': 'movie'},
              {'id': 3, 'title': 'Station', 'type': 'channel'},
              {'id': 4, 'title': 'ملودی باکس'},
            ])
            .map((e) => e.id),
        [1],
      );
    },
  );
  test(
    'home exposes only film discovery, never updater/support/public feeds',
    () async {
      final adapter = fixtures.StubAdapter(
        (_) => fixtures.jsonBody({
          'posters': [
            {'id': 1, 'title': 'Film'},
            {'id': 2, 'title': 'ملودی باکس'},
          ],
          'genres': [],
          'slides': [],
          'channels': [
            {'id': 3, 'title': 'Station'},
          ],
          'public_playlists': [],
          'news': {'title': 'Original news'},
          'support': 'https://t.me/support',
          'latest_version': '100',
          'settings': {'installer': 'https://example.com/latest.apk'},
          'unknown_promotion': 'https://t.me/original',
        }),
      );
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      final home = await api.home();
      expect(home.keys.toSet(), {'posters', 'genres', 'slides'});
      expect((home['posters'] as List).length, 1);
    },
  );
  test(
    'removed API wrappers cannot issue public-playlist/live-channel requests',
    () async {
      final adapter = fixtures.StubAdapter(
        (_) => fixtures.jsonBody([
          {'id': 1, 'title': 'Old entry'},
        ]),
      );
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      expect(await api.channels(), isEmpty);
      expect(await api.categories(), isEmpty);
      expect(await api.playlists(), isEmpty);
      expect(await api.playlistItems(1), isEmpty);
      await expectLater(api.channel(1), throwsA(isA<ApiException>()));
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'generic paths and query maps cannot bypass removed endpoint policy',
    () async {
      final adapter = fixtures.StubAdapter((_) => fixtures.jsonBody([]));
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      for (final path in [
        'channel/by/1/${ApiService.sharedKey}/',
        'news/all/',
        'updates/latest/',
      ]) {
        await expectLater(api.get(path), throwsA(isA<ApiException>()));
      }
      await expectLater(
        api.get(
          '${api.hostRoot}/api-user/newapi/like.php',
          query: {'action': 'showlist'},
        ),
        throwsA(isA<ApiException>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'a raw page containing only hidden items still has a continuation',
    () async {
      final adapter = fixtures.StubAdapter(
        (_) => fixtures.jsonBody([
          {'id': 2, 'title': 'ملودی باکس', 'type': 'movie'},
        ]),
      );
      final api = ApiService(dio: Dio()..httpClientAdapter = adapter);
      final page = await api.catalog(page: 5);
      expect(page, isEmpty);
      expect((page as CatalogPage).nextPage, 6);
      final search = await api.search('film', page: 3);
      expect(search, isEmpty);
      expect((search as CatalogPage).nextPage, 4);
    },
  );
  test(
    'stored model round trips cannot retain hidden promotional metadata',
    () {
      final title = TitleRecord.fromJson({
        'id': 1,
        'title': 'Film',
        'support': 'https://t.me/original',
        'news': ['Original app news'],
        'sources': [
          {'id': 1, 'url': 'https://example.com/film.mp4'},
          {'id': 2, 'url': 'https://example.com/new.apk'},
        ],
      });
      final encoded = jsonEncode(title.toJson());
      expect(encoded.contains('t.me'), isFalse);
      expect(encoded.contains('new.apk'), isFalse);
      expect(title.sources, hasLength(1));
      expect(TitleRecord.fromJson({'id': 8, 'title': 'ملودی باکس'}).id, 0);
    },
  );
}
