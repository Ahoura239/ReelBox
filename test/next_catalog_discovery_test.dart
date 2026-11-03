import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/catalog_discovery.dart';
import 'package:reelbox/data/models.dart';

class DiscoveryFixtureApi extends ApiService {
  final calls = <Map<String, dynamic>>[];
  dynamic response = <dynamic>[];
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add({'path': path, 'query': query});
    return response;
  }

  @override
  Future<List<TitleRecord>> bestRandom({
    bool byYear = false,
    int page = 1,
  }) async {
    final rows = discoveryRows(
      await get('fixture', query: {'action': 'best-rand-top', 'pageno': page}),
    );
    return CatalogPage(
      decodeTitles(rows),
      nextPage: rows.isEmpty ? null : page + 1,
    );
  }

  @override
  Future<List<TitleRecord>> search(
    String query, {
    int page = 1,
    bool english = false,
  }) async {
    final rows = discoveryRows(
      await get(
        'fixture',
        query: {
          'action': english ? 'search-movie-en' : 'search-movie',
          'q': query,
          'pageno': page,
        },
      ),
    );
    return CatalogPage(
      decodeTitles(rows),
      nextPage: rows.isEmpty ? null : page + 1,
    );
  }

  final posterIds = <int>[];
  @override
  Future<TitleRecord> poster(int id) async {
    posterIds.add(id);
    return TitleRecord(id: id, title: 'Hydrated $id');
  }

  bool actorFails = false;
  @override
  Future<List<TitleRecord>> actorTitles(int id) async {
    if (actorFails) throw const ApiException('Unavailable');
    return [];
  }
}

void main() {
  test(
    'thematic and franchise directories use distinct observed PHP routes',
    () async {
      final api = DiscoveryFixtureApi()
        ..response = [
          {'id': 1, 'mazmon': 'Space'},
        ];
      final service = CatalogDiscovery(api);
      final themes = await service.directory(
        DiscoveryDirectory.themes,
        page: 2,
      );
      expect(themes.single['title'], 'Space');
      // Live public mazmon ignores pageno and returns the entire directory.
      expect(themes.nextPage, isNull);
      expect(api.calls.last['path'], endsWith('/api-user/filmahang/star.php'));
      expect((api.calls.last['query'] as Map)['action'], 'mazmon');
      expect((api.calls.last['query'] as Map)['key'], ApiService.actorKey);
      await service.directory(DiscoveryDirectory.franchises, page: 3);
      expect(api.calls.last['path'], endsWith('/api-user/newapi/like.php'));
      expect(api.calls.last['query'], {'action': 'colection', 'pageno': 3});
    },
  );

  test('most-shared hydrates IDs once in order and keeps raw cursor', () async {
    final api = DiscoveryFixtureApi()
      ..response = [
        {'id': '11'},
        {'id': '11'},
        {'id': 12},
      ];
    final result = await CatalogDiscovery(api).sharedTitles(page: 7);
    expect(result.map((t) => t.id), [11, 12]);
    expect(api.posterIds, [11, 12]);
    expect(result.nextPage, 8);
    expect((api.calls.single['query'] as Map)['action'], 'share');
    expect((api.calls.single['query'] as Map)['key'], ApiService.actorKey);
  });

  test(
    'search filters apply locally without truncating raw page cursor',
    () async {
      final api = DiscoveryFixtureApi()
        ..response = [
          {'id': 1, 'title': 'Film', 'type': 'movie', 'year': 2000},
        ];
      final result = await CatalogDiscovery(api).search(
        'query',
        page: 4,
        filter: const DiscoverySearchFilter(kind: 'serie', minimumYear: 2020),
      );
      expect(result, isEmpty);
      expect(result.nextPage, 5);
      expect(api.calls.single['query'], {
        'action': 'search-movie',
        'q': 'query',
        'pageno': 4,
      });
    },
  );

  test('actor empty filmography uses paged name search rather than repeating actor request', () async {
    final api = DiscoveryFixtureApi()
      ..response = [
        {'id': 1, 'title': 'Name result'},
      ];
    final loader = ActorFilmography(
      CatalogDiscovery(api),
      id: 4,
      name: 'Actor',
    );
    await loader.load(1);
    await loader.load(2);
    expect(loader.usingNameFallback, isTrue);
    expect((api.calls.last['query'] as Map)['pageno'], 2);
    expect((api.calls.last['query'] as Map)['q'], 'Actor');
  });

  test(
    'actor metadata handles nested role actor without using the role ID',
    () {
      final person = actorMetadata({
        'id': 90,
        'role': 'Lead',
        'actor': {
          'id': 7,
          'name': 'Person',
          'bio': 'Biography',
          'born': '1980',
          'height': '180',
        },
      });
      expect(person['id'], 7);
      expect(person['name'], 'Person');
      expect(person['role'], 'Lead');
      expect(person['bio'], 'Biography');
    },
  );

  test('continuation selects only current non-trailer source not expired history URL', () {
    const sources = [
      MediaSource(url: 'https://video.example/trailer', quality: 'Trailer'),
      MediaSource(id: 3, url: 'https://video.example/current', quality: '720p'),
    ];
    expect(
      currentHistorySource(sources, 'https://expired.example/file')?.id,
      3,
    );
    expect(currentHistorySource([], 'https://expired.example/file'), isNull);
  });

  test(
    'legacy discovery retains raw continuation even for invisible rows',
    () async {
      final api = DiscoveryFixtureApi()
        ..response = [
          {'id': 0, 'title': ''},
        ];
      final result = await CatalogDiscovery(api).suggestions(page: 4);
      expect(result, isEmpty);
      expect(result.nextPage, 5);
      expect(api.calls.single['query'], {
        'action': 'best-rand-top',
        'pageno': 4,
      });
      api.response = [];
      expect(
        (await CatalogDiscovery(api).suggestions(page: 5)).nextPage,
        isNull,
      );
    },
  );
}
