import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:reelbox/ui/common.dart';
import 'package:reelbox/ui/library.dart';
import 'package:shared_preferences/shared_preferences.dart';

const movie = TitleRecord(id: 42, title: 'Movie');
const channel = TitleRecord(id: 42, title: 'Channel', type: 'channel');

class SettingsLocalApi extends ApiService {
  int discoveryChecks = 0;
  @override
  Future<void> initialize({bool discover = true}) async {
    if (discover) discoveryChecks++;
  }
}

Future<void> mount(WidgetTester tester, AppState state, Widget page) async {
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('imported non-menu settings remain selected and editable', (
    tester,
  ) async {
    final state = AppState(api: SettingsLocalApi());
    addTearDown(state.dispose);
    final backup = jsonDecode(state.exportLibrary()) as Map<String, dynamic>;
    backup['settings'] = {
      ...state.prefs.toJson(),
      'defaultQuality': '2160p',
      'playbackSpeed': 1.75,
      'skipSeconds': 12,
      'subtitleColor': 0xFF12AB34,
      'subtitleBackground': 0x40123456,
    };
    await state.importLibrary(jsonEncode(backup));
    final original = state.prefs.toJson();
    await mount(tester, state, const SettingsPage());
    for (final setting in <String, Object>{
      'Default quality': '2160p',
      'Playback speed': 1.75,
      'Seek step': 12,
      'Subtitle color': 0xFF12AB34,
      'Subtitle background': 0x40123456,
    }.entries) {
      await tester.scrollUntilVisible(
        find.text(setting.key),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final tile = find.ancestor(
        of: find.text(setting.key),
        matching: find.byType(ListTile),
      );
      final dropdown = tester.widget<DropdownButton<dynamic>>(
        find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (widget) => widget is DropdownButton,
          ),
        ),
      );
      expect(dropdown.value, setting.value);
      expect(
        dropdown.items!.where((item) => item.value == setting.value).length,
        1,
      );
    }
    expect(state.prefs.toJson(), original);
    await tester.scrollUntilVisible(
      find.text('Playback speed'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    final speedTile = find.ancestor(
      of: find.text('Playback speed'),
      matching: find.byType(ListTile),
    );
    await tester.ensureVisible(speedTile);
    await tester.tap(
      find.descendant(
        of: speedTile,
        matching: find.byWidgetPredicate((widget) => widget is DropdownButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1×').last);
    await tester.pumpAndSettle();
    expect(state.prefs.playbackSpeed, 1.0);
    expect(state.prefs.defaultQuality, '2160p');
  });

  testWidgets(
    'discovery check reports retained trust without claiming success',
    (tester) async {
      final api = SettingsLocalApi();
      final state = AppState(api: api);
      addTearDown(state.dispose);
      await state.initialize(discover: false);
      await mount(tester, state, const SettingsPage());
      await tester.scrollUntilVisible(
        find.text('Refresh API server'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Refresh API server'));
      await tester.pumpAndSettle();
      expect(api.discoveryChecks, 1);
      expect(
        find.text(
          'Discovery check finished. The current trusted server is retained unless a verified replacement is accepted; success was not verified.',
        ),
        findsOneWidget,
      );
      expect(find.text('Server discovery completed'), findsNothing);
    },
  );

  testWidgets('More opens a factual privacy and local-data explanation', (
    tester,
  ) async {
    final state = AppState(api: SettingsLocalApi());
    addTearDown(state.dispose);
    await mount(tester, state, const MorePage());
    await tester.scrollUntilVisible(
      find.text('Privacy & your data'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Privacy & your data'));
    await tester.pumpAndSettle();
    for (final topic in [
      'On this device',
      'External API & media',
      'Sharing & backups',
      'Deleting local data',
      'Unencrypted HTTP media',
    ]) {
      await tester.scrollUntilVisible(
        find.text(topic),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(topic), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('notifications explain new-task scope and Android requirements', (
    tester,
  ) async {
    final state = AppState(api: SettingsLocalApi());
    addTearDown(state.dispose);
    await mount(tester, state, const SettingsPage());
    await tester.scrollUntilVisible(
      find.text('Notifications for new downloads'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Notifications for new downloads'), findsOneWidget);
    expect(
      find.textContaining(
        'Already-running Android jobs keep their original notification policy',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('OS-required foreground notifications may remain'),
      findsOneWidget,
    );
  });

  testWidgets(
    'legacy channel history is pruned while same-ID movie remains removable',
    (tester) async {
      final state = AppState(api: SettingsLocalApi());
      addTearDown(state.dispose);
      final backup = jsonDecode(state.exportLibrary()) as Map<String, dynamic>;
      backup['history'] = [
        WatchEntry(title: channel, positionSeconds: 30).toJson(),
        WatchEntry(title: movie, positionSeconds: 15).toJson(),
      ];
      await state.importLibrary(jsonEncode(backup));
      await mount(tester, state, const LibraryPage());
      expect(find.text('Watchlist (0)'), findsOneWidget);
      expect(find.text('Continue (1)'), findsOneWidget);
      await tester.tap(find.text('Continue (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Channel'), findsNothing);
      expect(find.text('Movie'), findsOneWidget);
      expect(state.history.single.title.toJson(), movie.toJson());
      expect(state.resumeSeconds(42), 15);
      expect(state.resumeSeconds(42, kind: 'channel'), 0);
      await tester.tap(find.byTooltip('Remove history'));
      await tester.pumpAndSettle();
      expect(state.history, isEmpty);
      expect(find.text('Continue (0)'), findsOneWidget);
      expect(find.text('Pick up where you left off'), findsOneWidget);
    },
  );

  testWidgets(
    'removed channel card has no bookmark action and preserves the same-ID movie',
    (tester) async {
      final state = AppState(api: SettingsLocalApi());
      addTearDown(state.dispose);
      await state.toggleSaved(movie);
      await mount(
        tester,
        state,
        const Scaffold(
          body: SizedBox(height: 244, child: PosterCard(title: channel)),
        ),
      );
      expect(find.text('Channel'), findsNothing);
      expect(find.byTooltip('Watchlist'), findsNothing);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
      expect(state.saved.single.toJson(), movie.toJson());
      expect(state.hasSaved(42, kind: 'channel'), isFalse);

      // Allowed cards still expose the real bookmark action for this ID.
      await mount(
        tester,
        state,
        const Scaffold(
          body: SizedBox(height: 244, child: PosterCard(title: movie)),
        ),
      );
      expect(find.text('Movie'), findsWidgets);
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Watchlist'));
      await tester.pumpAndSettle();
      expect(state.saved, isEmpty);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Watchlist'));
      await tester.pumpAndSettle();
      expect(state.saved.single.toJson(), movie.toJson());
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    },
  );
}
