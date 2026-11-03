import 'package:flutter/material.dart';

import 'package:reelbox/media/media_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:reelbox/ui/catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NextCatalogApi extends ApiService {
  final pages = <int>[];
  bool series = false;
  @override
  Future<TitleRecord> poster(int id) async => TitleRecord(
    id: id,
    title: 'Current title',
    type: series ? 'serie' : 'movie',
    sources: const [
      MediaSource(id: 5, url: 'https://video.example/current.mp4'),
    ],
  );
  @override
  Future<List<SeasonRecord>> seasons(int id) async => [
    const SeasonRecord(
      id: 1,
      title: 'Season one',
      episodes: [EpisodeRecord(id: 51, title: 'Episode one')],
    ),
  ];
  @override
  Future<List<Map<String, dynamic>>> roles(int id) async => [];
  @override
  Future<List<Map<String, dynamic>>> comments(int id) async => [];
  @override
  Future<List<Map<String, dynamic>>> subtitles(String kind, int id) async => [];
  bool failSecond = false;
  @override
  Future<void> initialize({bool discover = true}) async {}
  @override
  Future<Map<String, dynamic>> home() async => {
    'genres': [],
    'channels': [
      {'id': 8, 'title': 'Removed live', 'type': 'channel'},
    ],
  };
  @override
  Future<List<Tag>> genres() async => [const Tag(id: 2, title: 'Drama')];
  @override
  Future<List<Tag>> countries() async => [
    const Tag(id: 8, title: 'Country eight'),
  ];
  @override
  Future<List<Map<String, dynamic>>> actors({
    int page = 1,
    String search = '',
  }) async => page == 1
      ? [
          {
            'id': 7,
            'name': 'Real actor',
            'role': 'Lead',
            'bio': 'Actor biography',
            'born': '1980',
          },
        ]
      : [];
  @override
  Future<List<TitleRecord>> actorTitles(int id) async => [
    const TitleRecord(id: 72, title: 'Filmography title'),
  ];
  @override
  Future<List<TitleRecord>> catalog({
    String kind = 'movie',
    int genre = 0,
    int country = 0,
    String order = 'created',
    int page = 0,
  }) async {
    pages.add(page);
    if (page == 1 && failSecond) {
      failSecond = false;
      throw const ApiException('Offline');
    }
    return CatalogPage(
      page == 0
          ? []
          : page == 1
          ? [const TitleRecord(id: 2, title: 'Later raw page')]
          : [],
      nextPage: page < 2 ? page + 1 : null,
    );
  }

  @override
  Future<List<String>> trending() async => ['Trending term'];
  @override
  Future<List<TitleRecord>> bestRandom({
    bool byYear = false,
    int page = 1,
  }) async => [const TitleRecord(id: 41, title: 'Suggested real title')];
  @override
  Future<List<TitleRecord>> search(
    String query, {
    int page = 1,
    bool english = false,
  }) async => CatalogPage(
    page == 1 ? [const TitleRecord(id: 42, title: 'Query result')] : [],
    nextPage: page == 1 ? 2 : null,
  );
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      switch (query?['action']) {
        'best-rand-top' => [
          {'id': 41, 'title': 'Suggested real title'},
        ],
        'search-movie' || 'search-movie-en' =>
          query?['pageno'] == 1
              ? [
                  {'id': 42, 'title': 'Query result'},
                ]
              : [],
        _ => [],
      };
}

Future<AppState> mountNextCatalog(
  WidgetTester tester,
  NextCatalogApi api,
  Widget page, {
  bool compact = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(
    api: api,
    storage: await SharedPreferences.getInstance(),
  );
  await state.initialize(discover: false);
  if (compact) {
    await state.updateSettings(AppSettings.fromJson({'compactCatalog': true}));
  }
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets(
    'explicit episode watched marker is independent of playback progress',
    (tester) async {
      final api = NextCatalogApi()..series = true;
      final state = await mountNextCatalog(
        tester,
        api,
        const TitlePage(
          title: TitleRecord(id: 9, title: 'Series', type: 'serie'),
        ),
      );
      await tester.scrollUntilVisible(find.text('Season one'), 250);
      await tester.tap(find.text('Season one'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Mark watched'));
      await tester.tap(find.byTooltip('Mark watched'));
      await tester.pumpAndSettle();
      expect(state.isEpisodeWatched(9, 51), isTrue);
      expect(state.history, isEmpty);
      await tester.tap(find.byTooltip('Mark unwatched'));
      await tester.pumpAndSettle();
      expect(state.isEpisodeWatched(9, 51), isFalse);
    },
  );

  testWidgets(
    'home continuation fetches current source instead of replaying stale history URL',
    (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MediaPlatform.channel,
        (call) async {
          if (call.method == 'openExternal') {
            calls.add((call.arguments as Map)['url'] as String);
          }
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MediaPlatform.channel,
          null,
        ),
      );
      final state = await mountNextCatalog(
        tester,
        NextCatalogApi(),
        const DiscoverPage(),
      );
      await state.updateSettings(state.prefs.copyWith(externalPlayer: true));
      await state.recordWatch(
        const TitleRecord(id: 9, title: 'Stored history title'),
        sourceUrl: 'https://expired.example/stale.mp4',
        positionSeconds: 30,
        durationSeconds: 100,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Stored history title'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Stored history title'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stored history title'));
      await tester.pumpAndSettle();
      expect(calls, ['https://video.example/current.mp4']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'home has real actor shelf and country discovery, not live features',
    (tester) async {
      await mountNextCatalog(tester, NextCatalogApi(), const DiscoverPage());
      expect(find.text('Live channels'), findsNothing);
      expect(find.text('Removed live'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Real actor'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Real actor'));
      await tester.pumpAndSettle();
      expect(find.text('Actor biography'), findsOneWidget);
      expect(find.text('Filmography title'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Country eight'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Country eight'));
      await tester.pumpAndSettle();
      expect(find.byType(BrowsePage), findsOneWidget);
      expect(
        tester.widget<BrowsePage>(find.byType(BrowsePage)).initialCountry,
        8,
      );
    },
  );

  testWidgets(
    'empty search suggests titles and supports individual history deletion and help',
    (tester) async {
      final state = await mountNextCatalog(
        tester,
        NextCatalogApi(),
        const SearchPage(),
      );
      expect(find.text('Suggested real title'), findsOneWidget);
      await state.rememberSearch('Keep term');
      await state.rememberSearch('Delete term');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove Delete term'));
      await tester.pumpAndSettle();
      expect(state.searchHistory, ['Keep term']);
      expect(find.text('Search help'), findsNothing);
      await tester.tap(find.byTooltip('Search help'));
      await tester.pumpAndSettle();
      expect(find.textContaining('loaded search results'), findsOneWidget);
      await tester.tap(find.text('Advanced filters'));
      await tester.pumpAndSettle();
      expect(find.text('Minimum IMDb'), findsOneWidget);
    },
  );

  testWidgets(
    'automatic pagination follows empty raw pages and retains failed cursor',
    (tester) async {
      final api = NextCatalogApi()..failSecond = true;
      await mountNextCatalog(tester, api, const BrowsePage(initialCountry: 8));
      expect(api.pages, [0, 1]);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Later raw page'), findsOneWidget);
      expect(api.pages.take(3), [0, 1, 1]);
    },
  );

  testWidgets('compact catalog preference renders compact rows and count', (
    tester,
  ) async {
    await mountNextCatalog(
      tester,
      NextCatalogApi(),
      const BrowsePage(),
      compact: true,
    );
    expect(
      find.ancestor(
        of: find.text('Later raw page'),
        matching: find.byType(ListTile),
      ),
      findsOneWidget,
    );
    expect(find.text('1 titles loaded'), findsOneWidget);
  });

  testWidgets(
    'directory removes public playlists and adds observed shortcuts',
    (tester) async {
      await mountNextCatalog(
        tester,
        NextCatalogApi(),
        const DiscoveryDirectoryPage(),
      );
      expect(find.text('Public playlists'), findsNothing);
      await tester.scrollUntilVisible(find.text('Miniseries'), 250);
      await tester.tap(find.text('Miniseries'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'مینی سریال',
      );
    },
  );
}
