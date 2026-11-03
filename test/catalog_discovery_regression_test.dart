import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/ui/catalog.dart';

import 'catalog_widget_test.dart' show CatalogApi, mountCatalog;

class DiscoveryApi extends CatalogApi {
  @override
  Future<List<Map<String, dynamic>>> actors({
    int page = 1,
    String search = '',
  }) async => [];
  @override
  Future<List<Map<String, dynamic>>> playlists({
    bool mine = false,
    String userId = '',
    int page = 1,
  }) async => [];
  @override
  Future<List<Map<String, dynamic>>> curatedLinks({bool best = false}) async =>
      [];
  @override
  Future<List<TitleRecord>> bestRandom({
    bool byYear = false,
    int page = 1,
  }) async => [];
}

Future<void> openDirectory(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Explore more'));
  await tester.pumpAndSettle();
}

void main() {
  for (final preset in [
    ('Best titles', 'mixed', 0, 'rating'),
    ('Newest titles', 'mixed', 0, 'created'),
    ('Popular titles', 'mixed', 0, 'rating'),
    ('Top 250 movies', 'movie', 0, 'imdb'),
    ('Top 250 series', 'serie', 0, 'imdb'),
    ('Korean series', 'serie', 36, 'created'),
    ('Chinese / Japanese series', 'serie', 37, 'created'),
    ('Turkish series', 'serie', 35, 'created'),
    ('Indian series', 'serie', 38, 'created'),
    ('Indian movies', 'movie', 38, 'created'),
    ('Most-viewed movies', 'movie', 0, 'views'),
    ('Most-viewed series', 'serie', 0, 'views'),
  ]) {
    testWidgets('${preset.$1} uses the original catalog contract', (
      tester,
    ) async {
      final api = DiscoveryApi();
      await mountCatalog(tester, api, const DiscoverPage());
      await openDirectory(tester);
      await tester.scrollUntilVisible(find.text(preset.$1), 300);
      await tester.ensureVisible(find.text(preset.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(preset.$1));
      await tester.pumpAndSettle();
      expect(api.catalogCalls, [
        for (final page in [0, 1, 2])
          {
            'kind': preset.$2,
            'genre': preset.$3,
            'country': 0,
            'order': preset.$4,
            'page': page,
          },
      ]);
    });
  }

  for (final entry in [
    ('Actors', ActorsPage),

    ('Editor picks', CuratedPage),
    ('Best collections', CuratedPage),
    ('Best by year', RecommendationsPage),
  ]) {
    testWidgets('Discover reaches ${entry.$1}', (tester) async {
      await mountCatalog(tester, DiscoveryApi(), const DiscoverPage());
      await openDirectory(tester);
      await tester.scrollUntilVisible(find.text(entry.$1), 300);
      await tester.ensureVisible(find.text(entry.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$1));
      await tester.pumpAndSettle();
      expect(find.byType(entry.$2), findsOneWidget);
      if (entry.$1 == 'Best by year') {
        expect(
          tester
              .widget<RecommendationsPage>(find.byType(RecommendationsPage))
              .byYear,
          isTrue,
        );
      }
    });
  }
}
