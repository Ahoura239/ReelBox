import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/app.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:reelbox/ui/library.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalApi extends ApiService {
  @override
  Future<void> initialize({bool discover = true}) async {}
  @override
  Future<Map<String, dynamic>> home() async => {
    'genres': [],
    'actors': [],
    'countries': [],
  };
  @override
  Future<List<Map<String, dynamic>>> actors({
    int page = 1,
    String search = '',
  }) async => [];
  @override
  Future<List<Tag>> countries() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppState> state() async {
    final s = AppState(api: _LocalApi());
    await s.initialize(discover: false);
    addTearDown(s.dispose);
    return s;
  }

  Widget host(AppState s, Widget child) => AppScope(
    state: s,
    child: MaterialApp(home: child),
  );

  testWidgets(
    'fresh app routes through introduction before exposing navigation',
    (tester) async {
      final s = await state();
      expect(s.prefs.introCompleted, false);
      await tester.pumpWidget(MyApp(state: s));
      await tester.pumpAndSettle();
      expect(find.byType(FirstRunIntroPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byKey(const Key('intro-skip')));
      await tester.pumpAndSettle();
      expect(s.prefs.introCompleted, true);
      expect(find.byType(FirstRunIntroPage), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );

  testWidgets(
    'counted library tabs remain readable and reachable with large text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await state();
      await tester.pumpWidget(
        host(
          s,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const LibraryPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = find.text('Collections (0)');
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      final render = tester.renderObject<RenderBox>(label);
      expect(
        render.size.width,
        greaterThanOrEqualTo(
          render.getMaxIntrinsicWidth(double.infinity) - 0.1,
        ),
      );
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['en', 'fa']) {
    testWidgets(
      'More shares independent app information in $locale without an invented install link',
      (tester) async {
        const channel = MethodChannel('dev.fluttercommunity.plus/share');
        final payloads = <Map>[];
        final methods = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            methods.add(call.method);
            payloads.add(call.arguments as Map);
            return 'fixture.receiver';
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final s = await state();
        await s.updateSettings(s.prefs.copyWith(locale: locale));
        await tester.pumpWidget(host(s, const MorePage()));
        expect(payloads, isEmpty);
        final action = find.byKey(const Key('share-reelbox'));
        await tester.scrollUntilVisible(action, 300);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(payloads, hasLength(1));
        expect(methods, ['share']);
        expect(
          payloads.single['text'],
          locale == 'en'
              ? 'Reelbox — an account-free film and series client with a private, device-local library'
              : 'Reelbox — فیلم و سریال، با کتابخانه خصوصی روی دستگاه و بدون نیاز به حساب کاربری',
        );
        expect(payloads.single['title'], 'Reelbox');
        expect(
          payloads.single['text'],
          isNot(
            matches(
              RegExp(
                r'https?://|telegram|t\.me/|ملودی|نورتون',
                caseSensitive: false,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'unavailable app sharing shows a safe error rather than native details',
    (tester) async {
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'fixture',
          message: 'private native fixture detail',
        );
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final s = await state();
      await tester.pumpWidget(host(s, const MorePage()));
      final action = find.byKey(const Key('share-reelbox'));
      await tester.scrollUntilVisible(action, 300);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        find.text('Sharing is unavailable on this device'),
        findsOneWidget,
      );
      expect(
        find.textContaining('private native fixture detail'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('first-run skip persists completion without touching library', (
    tester,
  ) async {
    final s = await state();
    await tester.pumpWidget(host(s, const FirstRunIntroPage()));
    await tester.tap(find.byKey(const Key('intro-skip')));
    await tester.pumpAndSettle();
    expect(s.prefs.introCompleted, true);
  });
  testWidgets('first-run finish persists completion', (tester) async {
    final s = await state();
    await tester.pumpWidget(host(s, const FirstRunIntroPage()));
    await tester.tap(find.byKey(const Key('intro-complete')));
    await tester.pumpAndSettle();
    expect(s.prefs.introCompleted, true);
  });
  testWidgets(
    'more exposes no removed service links and about uses runtime package info',
    (tester) async {
      final s = await state();
      PackageInfo.setMockInitialValues(
        appName: 'Reelbox',
        packageName: 'org.reelbox.app',
        version: '8.9.10',
        buildNumber: '456',
        buildSignature: '',
      );
      await tester.pumpWidget(host(s, const MorePage()));
      expect(find.text('Live channels'), findsNothing);
      expect(find.text('Public playlists'), findsNothing);
      expect(find.text('Original service support'), findsNothing);
      await tester.scrollUntilVisible(find.text('About Reelbox'), 300);
      await tester.tap(find.text('About Reelbox'));
      await tester.pumpAndSettle();
      expect(find.textContaining('8.9.10'), findsOneWidget);
      expect(find.textContaining('456'), findsOneWidget);
      expect(find.textContaining('org.reelbox.app'), findsOneWidget);
      expect(find.text('Dart runtime'), findsOneWidget);
      expect(find.text('Playback engine'), findsOneWidget);
    },
  );
  testWidgets(
    'custom ARGB color and opacity save exact RGB without changing background',
    (tester) async {
      final s = await state();
      await tester.pumpWidget(host(s, const SettingsPage()));
      await tester.scrollUntilVisible(find.text('Custom subtitle color'), 450);
      await tester.tap(find.text('Custom subtitle color'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('custom-color-hex')),
        '12345678',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('custom-color-opacity')));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Save'),
        ),
      );
      await tester.pumpAndSettle();
      expect(s.prefs.subtitleColor & 0xFFFFFF, 0x345678);
      expect(s.prefs.subtitleColor >> 24, inInclusiveRange(1, 254));
      expect(s.prefs.subtitleBackground, 0x80000000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings safely displays imported custom values and resets subtitle style only',
    (tester) async {
      final s = await state();
      await s.updateSettings(
        s.prefs.copyWith(
          subtitleFontFamily: 'My Custom Font',
          subtitleColor: 0x12123456,
          subtitleFontSize: 72,
          playbackSpeed: 1.7,
          parallelDownloads: 7,
          playerVolume: 0.33,
        ),
      );
      await tester.pumpWidget(host(s, const SettingsPage()));
      await tester.scrollUntilVisible(
        find.byKey(const Key('reset-subtitle-style')),
        450,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('reset-subtitle-style')));
      await tester.pumpAndSettle();
      expect(s.prefs.subtitleColor, 0xFFFFFFFF);
      expect(s.prefs.parallelDownloads, 7);
      expect(s.prefs.playbackSpeed, 1.7);
    },
  );
}
