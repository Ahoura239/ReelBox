import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/ui/catalog.dart';

import 'catalog_widget_test.dart' show CatalogApi, mountCatalog;

class CollisionApi extends CatalogApi {
  int channelCalls = 0;
  int posterCalls = 0;

  @override
  Future<TitleRecord> channel(int id) async {
    channelCalls++;
    return TitleRecord(id: id, title: 'Channel fixture', type: 'channel');
  }

  @override
  Future<TitleRecord> poster(int id) {
    posterCalls++;
    return super.poster(id);
  }
}

void main() {
  testWidgets(
    'legacy channel detail is blocked without changing a same-ID saved movie',
    (tester) async {
      final api = CollisionApi();
      final state = await mountCatalog(
        tester,
        api,
        const TitlePage(
          title: TitleRecord(id: 7, title: 'Channel fixture', type: 'channel'),
        ),
      );
      addTearDown(state.dispose);
      const movie = TitleRecord(id: 7, title: 'Movie fixture');
      await state.toggleSaved(movie);
      await tester.pumpAndSettle();
      expect(find.text('This title is unavailable.'), findsOneWidget);
      expect(find.text('Add to watchlist'), findsNothing);
      expect(find.text('In watchlist'), findsNothing);
      expect(api.channelCalls, 0);
      expect(api.posterCalls, 0);
      expect(state.saved.single.toJson(), movie.toJson());
      expect(state.hasSaved(7), isTrue);
      expect(state.hasSaved(7, kind: 'channel'), isFalse);
      expect(find.text('Try again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final series in [false, true]) {
    testWidgets(
      '${series ? 'series' : 'movie'} detail keeps allowed watchlist identity after a blocked channel mutation',
      (tester) async {
        final api = CollisionApi()..series = series;
        final state = await mountCatalog(
          tester,
          api,
          TitlePage(
            title: TitleRecord(
              id: 7,
              title: 'Allowed fixture',
              type: series ? 'serie' : 'movie',
            ),
          ),
        );
        addTearDown(state.dispose);
        await state.toggleSaved(
          const TitleRecord(id: 7, title: 'Channel fixture', type: 'channel'),
        );
        await tester.pumpAndSettle();
        expect(state.saved, isEmpty);
        expect(find.text('Add to watchlist'), findsOneWidget);
        await tester.ensureVisible(find.text('Add to watchlist'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add to watchlist'));
        await tester.pumpAndSettle();
        expect(state.saved.single.id, 7);
        expect(state.saved.single.isSeries, series);
        expect(state.hasSaved(7), isTrue);
        expect(state.hasSaved(7, kind: 'channel'), isFalse);
        expect(find.text('In watchlist'), findsOneWidget);
        await tester.ensureVisible(find.text('In watchlist'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('In watchlist'));
        await tester.pumpAndSettle();
        expect(state.saved, isEmpty);
        expect(find.text('Add to watchlist'), findsOneWidget);
        expect(api.posterCalls, 1);
        expect(api.channelCalls, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
