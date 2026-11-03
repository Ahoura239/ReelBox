// Optional host-rendered UI evidence; not Android device verification.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/app.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:reelbox/ui/library.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CaptureApi extends ApiService {
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
  @override
  Future<List<Tag>> genres() async => [];
  @override
  Future<List<String>> trending() async => [];
  @override
  Future<List<TitleRecord>> bestRandom({
    bool byYear = false,
    int page = 1,
  }) async => [];
}

void main() {
  testWidgets(
    'mobile local-library and settings UI renders in English and Persian',
    (tester) async {
      await tester.runAsync(() async {
        final font = File(
          Platform.environment['REELBOX_TEST_FONT'] ??
              '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        );
        final bytes = await font.readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(bytes.buffer.asByteData()))).load();
        await (FontLoader(
          'Ahem',
        )..addFont(Future.value(bytes.buffer.asByteData()))).load();
        final icons = await File(
          Platform.environment['REELBOX_ICON_FONT'] ?? '/root/developer-tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(icons.buffer.asByteData()))).load();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      // Explicitly invoked test harness; kept outside default test discovery.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
        api: _CaptureApi(),
        storage: await SharedPreferences.getInstance(),
      );
      await state.initialize(discover: false);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MyApp(state: state),
        ),
      );
      await tester.pumpAndSettle();
      final output = Directory(
        Platform.environment['REELBOX_SCREENSHOT_DIR'] ??
            '${Directory.current.path}/build/ui-verification',
      );
      await tester.runAsync(() => output.create(recursive: true));
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(find.byType(FirstRunIntroPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await capture('intro-en');
      await state.updateSettings(state.prefs.copyWith(locale: 'fa'));
      await tester.pumpAndSettle();
      expect(find.byType(FirstRunIntroPage), findsOneWidget);
      await capture('intro-fa');
      await state.updateSettings(
        state.prefs.copyWith(locale: 'en', introCompleted: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library').last);
      expect(find.byType(NavigationBar), findsOneWidget);
      await capture('library-en');
      await tester.tap(find.text('More').last);
      await capture('more-en');
      await tester.tap(find.text('Settings'));
      await capture('settings-en');
      await state.updateSettings(state.prefs.copyWith(locale: 'fa'));
      await capture('settings-fa');
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
