import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_platform.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/ui/catalog.dart';

import 'catalog_widget_test.dart' show CatalogApi, mountCatalog;

class QualityApi extends CatalogApi {
  @override
  Future<TitleRecord> poster(int id) async => TitleRecord(
    id: id,
    title: 'Quality fixture',
    sources: const [
      MediaSource(
        id: 1,
        quality: '720p',
        type: 'mp4',
        url: 'https://media.example/720.mp4',
      ),
      MediaSource(
        id: 2,
        quality: '1080p',
        type: 'mp4',
        url: 'https://media.example/1080.mp4',
      ),
    ],
  );
}

void main() {
  testWidgets(
    'ask quality waits for an explicit source choice and supports cancel',
    (tester) async {
      final state = await mountCatalog(
        tester,
        QualityApi(),
        const TitlePage(title: TitleRecord(id: 7, title: 'Fixture')),
      );
      expect(state.prefs.defaultQuality, 'ask');
      final play = find.byKey(const ValueKey('play-preferred'));
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(find.text('Choose a source'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a source'), findsNothing);
      expect(find.byType(TitlePage), findsOneWidget);
    },
  );

  testWidgets('preferred quality is used by the primary play action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MediaPlatform.channel,
      (call) async {
        calls.add((call.arguments as Map)['url'] as String);
        return true;
      },
    );
    final state = await mountCatalog(
      tester,
      QualityApi(),
      const TitlePage(title: TitleRecord(id: 7, title: 'Fixture')),
    );
    await state.updateSettings(
      state.prefs.copyWith(externalPlayer: true, defaultQuality: '1080'),
    );
    await tester.pumpAndSettle();
    final play = find.byKey(const ValueKey('play-preferred'));
    expect(play, findsOneWidget);
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(calls, ['https://media.example/1080.mp4']);
    debugDefaultTargetPlatformOverride = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MediaPlatform.channel,
      null,
    );
  });

  testWidgets(
    'external-player preference dispatches selected media to native player',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MediaPlatform.channel,
        (call) async {
          if (call.method == 'openExternal') {
            calls.add((call.arguments as Map)['url'] as String);
            return true;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MediaPlatform.channel,
          null,
        ),
      );
      final state = await mountCatalog(
        tester,
        CatalogApi(),
        const TitlePage(title: TitleRecord(id: 7, title: 'Fixture')),
      );
      await state.updateSettings(state.prefs.copyWith(externalPlayer: true));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Play').first);
      await tester.tap(find.byTooltip('Play').first);
      await tester.pumpAndSettle();
      expect(calls, ['https://media.example/movie.mp4']);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
