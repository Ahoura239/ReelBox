import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/media/media_platform.dart';
import 'package:reelbox/ui/catalog.dart';

import 'next_catalog_ui_test.dart' show NextCatalogApi, mountNextCatalog;

class PolicyCatalogApi extends NextCatalogApi {
  @override
  Future<TitleRecord> poster(int id) async => const TitleRecord(
    id: 9,
    title: 'Independent title',
    sources: [
      MediaSource(url: 'https://t.me/removed_channel'),
      MediaSource(
        url: 'https://video.example/embed',
        type: 'embed',
        quality: 'Embedded video',
      ),
    ],
  );
}

void main() {
  testWidgets(
    'blocked title names never appear in the header and retry stays handled',
    (tester) async {
      await mountNextCatalog(
        tester,
        PolicyCatalogApi(),
        const TitlePage(title: TitleRecord(id: 99, title: 'ملودی باکس')),
      );
      expect(find.text('ملودی باکس'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ملودی باکس'), findsNothing);
    },
  );
  testWidgets(
    'title sharing contains plain title and no original share destination',
    (tester) async {
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final payloads = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        (call) async {
          payloads.add(call.arguments as Map);
          return 'success';
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          shareChannel,
          null,
        ),
      );
      await mountNextCatalog(
        tester,
        NextCatalogApi(),
        const TitlePage(title: TitleRecord(id: 9, title: 'Initial')),
      );
      await tester.ensureVisible(find.text('Share'));
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(payloads.single['text'], 'Current title');
      expect('${payloads.single}', isNot(contains('/share/')));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('blocked destinations do not render sources or website actions', (
    tester,
  ) async {
    await mountNextCatalog(
      tester,
      PolicyCatalogApi(),
      const TitlePage(title: TitleRecord(id: 9, title: 'Initial')),
    );
    expect(find.text('Website'), findsNothing);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Copy source URL'), findsOneWidget);
  });

  testWidgets('embedded media uses native generic browser with video title', (
    tester,
  ) async {
    final payloads = <Map>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MediaPlatform.channel,
      (call) async {
        if (call.method == 'openEmbedded') payloads.add(call.arguments as Map);
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MediaPlatform.channel,
        null,
      ),
    );
    await mountNextCatalog(
      tester,
      PolicyCatalogApi(),
      const TitlePage(title: TitleRecord(id: 9, title: 'Initial')),
    );
    await tester.ensureVisible(find.byTooltip('Play'));
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(payloads.single, {
      'url': 'https://video.example/embed',
      'title': 'Independent title',
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('search help and advanced filters fit a small viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountNextCatalog(tester, NextCatalogApi(), const SearchPage());
    await tester.tap(find.byTooltip('Search help'));
    await tester.tap(find.text('Advanced filters'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
