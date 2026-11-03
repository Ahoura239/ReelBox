import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:reelbox/ui/catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CatalogApi extends ApiService {
  int homeCalls = 0;
  bool failHome = false;
  @override
  Future<Map<String, dynamic>> home() async {
    homeCalls++;
    if (failHome) throw Exception('Offline');
    return {
      'genres': [
        {
          'id': 2,
          'title': 'From the server',
          'posters': [const TitleRecord(id: 7, title: 'Real fixture').toJson()],
        },
      ],
    };
  }

  @override
  Future<void> initialize({bool discover = true}) async {}
  bool series = false;
  @override
  Future<TitleRecord> poster(int id) async => TitleRecord(
    id: id,
    title: 'Fixture detail',
    type: series ? 'serie' : 'movie',
    description: 'Actual fixture synopsis',
    genres: [const Tag(id: 2, title: 'Action')],
    sources: [
      const MediaSource(
        id: 1,
        quality: '1080p',
        type: 'mp4',
        url: 'https://media.example/movie.mp4',
      ),
      const MediaSource(
        id: 2,
        quality: 'Trailer',
        type: 'mp4',
        url: 'https://media.example/trailer.mp4',
      ),
    ],
  );
  @override
  Future<List<SeasonRecord>> seasons(int id) async => [
    const SeasonRecord(
      id: 1,
      title: 'Season 1',
      episodes: [
        EpisodeRecord(
          id: 51,
          title: 'Episode 1',
          sources: [
            MediaSource(
              id: 1,
              quality: '720p',
              url: 'https://media.example/1.mp4',
            ),
          ],
        ),
        EpisodeRecord(
          id: 52,
          title: 'Episode 2',
          sources: [
            MediaSource(
              id: 2,
              quality: '720p',
              url: 'https://media.example/2.mp4',
            ),
          ],
        ),
      ],
    ),
  ];
  @override
  Future<List<Map<String, dynamic>>> roles(int posterId) async => [];
  @override
  Future<List<Map<String, dynamic>>> comments(int posterId) async => [
    {'id': 1, 'user': 'Viewer', 'content': 'SGVsbG8=', 'created': 'Today'},
  ];
  @override
  Future<List<Map<String, dynamic>>> subtitles(String kind, int id) async => [];
  final catalogCalls = <Map<String, dynamic>>[];
  final searchCalls = <Map<String, dynamic>>[];
  @override
  Future<List<Tag>> genres() async => [const Tag(id: 3, title: 'Animation')];
  @override
  Future<List<Tag>> countries() async => [const Tag(id: 1, title: 'Country')];
  @override
  Future<List<Tag>> categories() async => [];
  @override
  Future<List<TitleRecord>> catalog({
    String kind = 'movie',
    int genre = 0,
    int country = 0,
    String order = 'created',
    int page = 0,
  }) async {
    catalogCalls.add({
      'kind': kind,
      'genre': genre,
      'country': country,
      'order': order,
      'page': page,
    });
    return page < 2 ? [TitleRecord(id: page + 20, title: 'Page $page')] : [];
  }

  @override
  Future<List<String>> trending() async => ['سرچ'];
  @override
  Future<List<TitleRecord>> search(
    String query, {
    int page = 1,
    bool english = false,
  }) async {
    searchCalls.add({'q': query, 'page': page, 'english': english});
    return CatalogPage(
      page == 1 ? [TitleRecord(id: 41, title: 'Result $query')] : [],
      nextPage: null,
    );
  }

  @override
  Future<List<TitleRecord>> recommended(int genre, {int page = 1}) async => [];
}

Future<AppState> mountCatalog(
  WidgetTester tester,
  CatalogApi api,
  Widget page,
) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(
    api: api,
    storage: await SharedPreferences.getInstance(),
  );
  await state.initialize(discover: false);
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: page),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets(
    'movie detail exposes public quality, local watchlist, read-only decoded comments',
    (tester) async {
      final api = CatalogApi();
      final state = await mountCatalog(
        tester,
        api,
        const TitlePage(title: TitleRecord(id: 7, title: 'Fixture')),
      );
      expect(find.text('Fixture detail'), findsWidgets);
      await tester.ensureVisible(find.text('Add to watchlist'));
      await tester.tap(find.text('Add to watchlist'));
      await tester.pumpAndSettle();
      expect(state.hasSaved(7), isTrue);
      await tester.ensureVisible(find.text('1080p'));
      expect(find.text('1080p'), findsOneWidget);
      await tester.ensureVisible(find.text('Comments'));
      await tester.tap(find.text('Comments'));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.textContaining('Sign in'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets('series detail uses nested real seasons and episode sources', (
    tester,
  ) async {
    final api = CatalogApi()..series = true;
    await mountCatalog(
      tester,
      api,
      const TitlePage(
        title: TitleRecord(id: 7, title: 'Fixture', type: 'serie'),
      ),
    );
    await tester.ensureVisible(find.text('Season 1'));
    await tester.tap(find.text('Season 1'));
    await tester.pumpAndSettle();
    expect(find.text('Episode 1'), findsOneWidget);
    expect(find.text('Episode 2'), findsOneWidget);
    await tester.ensureVisible(find.text('Episode 1'));
    await tester.tap(find.text('Episode 1'));
    await tester.pumpAndSettle();
    expect(find.text('720p'), findsOneWidget);
    expect(find.byTooltip('Play'), findsWidgets);
  });
  testWidgets(
    'browse anime preserves mixed genre 3 across automatically loaded pages',
    (tester) async {
      final api = CatalogApi();
      await mountCatalog(
        tester,
        api,
        const BrowsePage(initialKind: 'mixed', initialGenre: 3),
      );
      // Small real-result fixture pages are prefetched until the viewport is
      // filled or the upstream empty page is reached, without changing filters.
      expect(api.catalogCalls.map((call) => call['page']), [0, 1, 2]);
      for (final call in api.catalogCalls) {
        expect(call['kind'], 'mixed');
        expect(call['genre'], 3);
      }
      expect(find.text('Page 0'), findsOneWidget);
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('You’re all caught up'), findsOneWidget);
    },
  );
  testWidgets(
    'search submits Persian query and switches to English endpoint explicitly',
    (tester) async {
      final api = CatalogApi();
      await mountCatalog(tester, api, const SearchPage());
      await tester.scrollUntilVisible(
        find.text('سرچ'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('سرچ'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'فیلم');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.searchCalls.single, {
        'q': 'فیلم',
        'page': 1,
        'english': false,
      });
      await tester.tap(find.text('Advanced filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('English search'));
      await tester.tap(find.text('English search'));
      await tester.pumpAndSettle();
      expect(api.searchCalls.last['english'], true);
      expect(find.text('Result فیلم'), findsOneWidget);
    },
  );
  testWidgets('Discover displays server rail without refetching on rebuild', (
    tester,
  ) async {
    final api = CatalogApi();
    final state = await mountCatalog(tester, api, const DiscoverPage());
    expect(find.text('From the server'), findsOneWidget);
    expect(find.text('Real fixture'), findsWidgets);
    expect(api.homeCalls, 1);
    await state.toggleSaved(const TitleRecord(id: 12, title: 'Saved'));
    await tester.pumpAndSettle();
    expect(api.homeCalls, 1);
  });
}
