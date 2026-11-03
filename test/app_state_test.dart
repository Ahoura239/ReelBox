import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sourceUrl = 'https://media.example/video%2F17.mp4?token=a%2Bb&part=1';

TitleRecord _title(int id) => TitleRecord.fromJson({
  'id': id,
  'type': 'serie',
  'title': 'Title $id',
  'sources': [
    {'id': 520531, 'quality': '1080p', 'type': 'mp4', 'url': _sourceUrl},
  ],
  'metadata': {'original': 'محلی'},
});

class _LocalApi extends ApiService {
  int initializeCalls = 0;
  bool? lastDiscover;

  @override
  Future<void> initialize({bool discover = true}) async {
    initializeCalls++;
    lastDiscover = discover;
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      throw StateError('Local state must not request catalog data');

  @override
  Future<dynamic> post(String path, Map<String, dynamic> form) =>
      throw StateError('Local state must not mutate network state');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'watchlist and settings persist locally with exact source metadata',
    () async {
      final api = _LocalApi();
      final store = await SharedPreferences.getInstance();
      final state = AppState(api: api, storage: store);
      await state.initialize(discover: false);
      expect(api.initializeCalls, 1);
      expect(api.lastDiscover, isFalse);
      var notifications = 0;
      state.addListener(() => notifications++);
      final title = _title(17);
      await state.toggleSaved(title);
      expect(state.hasSaved(17), isTrue);
      expect(state.saved.single.sources.single.url, _sourceUrl);
      await state.updateSettings(
        state.prefs.copyWith(locale: 'fa', preferredGenres: [3]),
      );
      expect(state.locale, 'fa');
      expect(state.selectedGenres, [3]);
      expect(notifications, 2);
      final restored = AppState(api: _LocalApi(), storage: store);
      await restored.initialize(discover: false);
      expect(restored.saved.single.toJson(), title.toJson());
      expect(restored.prefs.toJson(), state.prefs.toJson());
      expect(() => restored.saved.clear(), throwsUnsupportedError);
      await restored.toggleSaved(title);
      expect(restored.saved, isEmpty);
      await restored.toggleSaved(title);
      await restored.removeSaved(17);
      expect(restored.hasSaved(17), isFalse);
      state.dispose();
      restored.dispose();
    },
  );

  test(
    'episode resume is isolated, updates reorder and removals are exact',
    () async {
      final state = AppState(api: _LocalApi());
      await state.initialize(discover: false);
      final title = _title(9);
      await state.recordWatch(title, positionSeconds: 5, durationSeconds: 100);
      await state.recordWatch(
        title,
        episodeId: 101,
        episodeTitle: 'Episode 1',
        sourceUrl: _sourceUrl,
        positionSeconds: 25,
        durationSeconds: 100,
      );
      await state.recordWatch(
        title,
        episodeId: 102,
        episodeTitle: 'Episode 2',
        positionSeconds: 75,
        durationSeconds: 100,
      );
      expect(state.resumeSeconds(9), 5);
      expect(state.resumeSeconds(9, episodeId: 101), 25);
      expect(state.resumeSeconds(9, episodeId: 102), 75);
      expect(state.resumeSeconds(10, episodeId: 101), 0);
      expect(state.history.first.progress, 0.75);
      await state.recordWatch(
        title,
        episodeId: 101,
        episodeTitle: 'Episode 1',
        sourceUrl: _sourceUrl,
        positionSeconds: 40,
        durationSeconds: 100,
      );
      expect(state.history.length, 3);
      expect(state.history.first.episodeId, 101);
      expect(state.history.first.sourceUrl, _sourceUrl);
      expect(state.history.first.updatedAt.isUtc, isTrue);
      final restored = AppState(api: _LocalApi());
      await restored.initialize(discover: false);
      expect(restored.resumeSeconds(9, episodeId: 101), 40);
      expect(restored.history.first.episodeTitle, 'Episode 1');
      expect(restored.history.first.sourceUrl, _sourceUrl);
      expect(restored.history.first.toJson(), state.history.first.toJson());
      await state.updateSettings(state.prefs.copyWith(resumePlayback: false));
      expect(state.resumeSeconds(9, episodeId: 101), 0);
      expect(state.history.first.positionSeconds, 40);
      await state.removeHistory(9, episodeId: 101);
      expect(state.history.map((entry) => entry.episodeId), [102, null]);
      await state.removeHistory(9);
      expect(state.history.single.episodeId, 102);
      await state.clearHistory();
      expect(state.history, isEmpty);
      state.dispose();
      restored.dispose();
    },
  );

  test(
    'watch progress clamps safely and invalid positions reject without changes',
    () async {
      final state = AppState(api: _LocalApi());
      await state.recordWatch(
        _title(1),
        positionSeconds: 200,
        durationSeconds: 100,
      );
      expect(state.history.single.progress, 1);
      await state.recordWatch(_title(2));
      expect(state.history.first.progress, 0);
      await expectLater(
        state.recordWatch(_title(1), positionSeconds: double.nan),
        throwsArgumentError,
      );
      await expectLater(
        state.recordWatch(_title(1), durationSeconds: -1),
        throwsArgumentError,
      );
      expect(state.history.length, 2);
      state.dispose();
    },
  );

  test(
    'search history trims, deduplicates case-insensitively and caps at 30',
    () async {
      final state = AppState(api: _LocalApi());
      await state.rememberSearch('  Dune  ');
      await state.rememberSearch('Alien');
      await state.rememberSearch('dUnE');
      await state.rememberSearch('   ');
      expect(state.searchHistory, ['dUnE', 'Alien']);
      await state.removeSearch(' DUNE ');
      expect(state.searchHistory, ['Alien']);
      await Future.wait(
        List.generate(35, (i) => state.rememberSearch('Query $i')),
      );
      expect(state.searchHistory.length, 30);
      expect(state.searchHistory.first, 'Query 34');
      expect(state.searchHistory.last, 'Query 5');
      final restored = AppState(api: _LocalApi());
      await restored.initialize(discover: false);
      expect(restored.searchHistory, state.searchHistory);
      await restored.clearSearchHistory();
      expect(restored.searchHistory, isEmpty);
      state.dispose();
      restored.dispose();
    },
  );

  test(
    'local collections have stable IDs and independent title membership',
    () async {
      final state = AppState(api: _LocalApi());
      final first = await state.createCollection('  Weekend  ');
      final second = await state.createCollection('Weekend');
      expect(first.name, 'Weekend');
      expect(first.id, isNot(second.id));
      await state.toggleCollectionTitle(first.id, _title(17));
      await state.toggleCollectionTitle(second.id, _title(17));
      await state.toggleCollectionTitle(first.id, _title(18));
      expect(state.collections.first.titles.map((title) => title.id), [17, 18]);
      expect(state.saved, isEmpty);
      await state.toggleCollectionTitle(first.id, _title(17));
      expect(state.collections.first.titles.single.id, 18);
      expect(state.collections.last.titles.single.id, 17);
      expect(
        () => state.collections.first.titles.clear(),
        throwsUnsupportedError,
      );
      final restored = AppState(api: _LocalApi());
      await restored.initialize(discover: false);
      expect(
        restored.collections.map((item) => item.toJson()),
        state.collections.map((item) => item.toJson()),
      );
      await restored.deleteCollection(first.id);
      expect(restored.collections.single.id, second.id);
      await expectLater(
        restored.toggleCollectionTitle('missing', _title(1)),
        throwsStateError,
      );
      await expectLater(restored.createCollection('  '), throwsArgumentError);
      state.dispose();
      restored.dispose();
    },
  );

  test(
    'versioned export/import replaces the entire library and persists it',
    () async {
      final state = AppState(api: _LocalApi());
      await state.toggleSaved(_title(17));
      await state.recordWatch(
        _title(17),
        episodeId: 41,
        episodeTitle: 'Forty one',
        sourceUrl: _sourceUrl,
        positionSeconds: 12.5,
        durationSeconds: 50,
      );
      await state.rememberSearch('سینما');
      final collection = await state.createCollection('Favorites');
      await state.toggleCollectionTitle(collection.id, _title(20));
      await state.updateSettings(
        state.prefs.copyWith(locale: 'fa', playbackSpeed: 2),
      );
      final exported = state.exportLibrary();
      final document = jsonDecode(exported) as Map<String, dynamic>;
      expect(document['format'], 'reelbox.library');
      expect(document['version'], 1);
      final imported = AppState(api: _LocalApi());
      await imported.toggleSaved(_title(99));
      var notifications = 0;
      imported.addListener(() => notifications++);
      await imported.importLibrary(exported);
      expect(imported.exportLibrary(), exported);
      expect(imported.hasSaved(99), isFalse);
      expect(imported.resumeSeconds(17, episodeId: 41), 12.5);
      expect(imported.collections.single.id, collection.id);
      expect(notifications, 1);
      final restored = AppState(api: _LocalApi());
      await restored.initialize(discover: false);
      expect(restored.exportLibrary(), exported);
      state.dispose();
      imported.dispose();
      restored.dispose();
    },
  );

  test(
    'corrupt import is atomic across memory, storage and notifications',
    () async {
      final store = await SharedPreferences.getInstance();
      final state = AppState(api: _LocalApi(), storage: store);
      await state.toggleSaved(_title(17));
      await state.recordWatch(_title(17), episodeId: 2, positionSeconds: 3);
      await state.rememberSearch('Keep');
      final original = state.exportLibrary();
      final stored = store.getString(AppState.storageKey);
      var notifications = 0;
      state.addListener(() => notifications++);
      final mutations = <void Function(Map<String, dynamic>)>[
        (doc) => doc['version'] = 2,
        (doc) => doc['version'] = '1',
        (doc) => doc['format'] = 'other',
        (doc) => doc.remove('saved'),
        (doc) => doc['settings'] = [],
        (doc) => doc['saved'] = [
          {'id': '17', 'title': 'Invalid'},
        ],
        (doc) => doc['saved'] = [doc['saved'][0], doc['saved'][0]],
        (doc) => doc['history'][0]['positionSeconds'] = -1,
        (doc) => doc['history'][0]['updatedAt'] = 'not a date',
        (doc) => doc['searchHistory'] = [42],
        (doc) => doc['collections'] = [
          {'id': '', 'name': 'Invalid', 'titles': []},
        ],
      ];
      for (final mutate in mutations) {
        final document = jsonDecode(original) as Map<String, dynamic>;
        mutate(document);
        await expectLater(
          state.importLibrary(jsonEncode(document)),
          throwsFormatException,
        );
        expect(state.exportLibrary(), original);
        expect(store.getString(AppState.storageKey), stored);
      }
      for (final text in ['not json', '[]', 'null', '{']) {
        await expectLater(state.importLibrary(text), throwsFormatException);
      }
      expect(notifications, 0);
      await state.rememberSearch('Still usable');
      expect(state.searchHistory.first, 'Still usable');
      state.dispose();
    },
  );

  test(
    'import limits history to latest 1000 and normalizes 30 searches',
    () async {
      final state = AppState(api: _LocalApi());
      final document =
          jsonDecode(state.exportLibrary()) as Map<String, dynamic>;
      final start = DateTime.utc(2026);
      document['history'] = List.generate(
        1005,
        (i) => WatchEntry(
          title: _title(i + 1),
          episodeId: 1,
          positionSeconds: i.toDouble(),
          updatedAt: start.add(Duration(seconds: i)),
        ).toJson(),
      );
      document['searchHistory'] = [
        '  Dune ',
        'dune',
        '',
        ...List.generate(35, (i) => 'Query $i'),
      ];
      await state.importLibrary(jsonEncode(document));
      expect(state.history.length, 1000);
      expect(state.history.first.title.id, 1005);
      expect(state.history.last.title.id, 6);
      expect(state.searchHistory.length, 30);
      expect(state.searchHistory.first, 'Dune');
      await state.recordWatch(_title(2000), episodeId: 7, positionSeconds: 20);
      expect(state.history.length, 1000);
      expect(state.history.first.title.id, 2000);
      expect(state.history.last.title.id, 7);
      state.dispose();
    },
  );

  test('clear resets preferences and all local state without clearing unrelated keys', () async {
    final store = await SharedPreferences.getInstance();
    await store.setString('unrelated.plugin.setting', 'keep');
    final state = AppState(api: _LocalApi(), storage: store);
    await state.toggleSaved(_title(1));
    await state.recordWatch(_title(1), positionSeconds: 5);
    await state.rememberSearch('Query');
    final collection = await state.createCollection('One');
    await state.toggleCollectionTitle(collection.id, _title(1));
    await state.updateSettings(state.prefs.copyWith(locale: 'fa'));
    await state.clearLocalData();
    expect(state.prefs.toJson(), AppSettings().toJson());
    expect(state.saved, isEmpty);
    expect(state.history, isEmpty);
    expect(state.searchHistory, isEmpty);
    expect(state.collections, isEmpty);
    expect(store.getString('unrelated.plugin.setting'), 'keep');
    final restored = AppState(api: _LocalApi(), storage: store);
    await restored.initialize(discover: false);
    expect(restored.exportLibrary(), state.exportLibrary());
    state.dispose();
    restored.dispose();
  });

  test('settings defaults, copyWith and JSON preserve every preference', () {
    final defaults = AppSettings();
    expect(defaults.locale, 'en');
    expect(defaults.theme, 'dark');
    expect(defaults.autoNext, isTrue);
    expect(defaults.resumePlayback, isTrue);
    expect(defaults.playbackSpeed, 1.0);
    expect(defaults.skipSeconds, 10);
    expect(defaults.introCompleted, isFalse);
    final changed = defaults.copyWith(
      introCompleted: true,
      locale: 'fa',
      theme: 'light',
      wifiOnlyDownloads: true,
      autoNext: false,
      resumePlayback: false,
      autoplay: true,
      externalPlayer: true,
      defaultQuality: '1080p',
      playbackSpeed: 1.5,
      skipSeconds: 30,
      subtitleFontSize: 32,
      subtitleColor: 0xFF00FF00,
      subtitleBackground: 0x40000000,
      subtitleDelay: -1.25,
      audioDelay: 0.5,
      orientation: 'landscape',
      preferredGenres: [3, 7],
      hideTrailers: true,
      downloadNotifications: false,
      dataSaver: true,
    );
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode(changed.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), changed.toJson());
    expect(defaults.locale, 'en');
    expect(restored.copyWith().toJson(), restored.toJson());
    expect(() => restored.preferredGenres.add(4), throwsUnsupportedError);
  });

  for (final introCompleted in <bool?>[null, false, true]) {
    test(
      'stored onboarding flag $introCompleted migrates without losing the library',
      () async {
        final store = await SharedPreferences.getInstance();
        final state = AppState(api: _LocalApi(), storage: store);
        final restored = AppState(api: _LocalApi(), storage: store);
        addTearDown(state.dispose);
        addTearDown(restored.dispose);
        final document =
            jsonDecode(state.exportLibrary()) as Map<String, dynamic>;
        final settings = document['settings'] as Map<String, dynamic>;
        settings['locale'] = 'fa';
        settings['playbackSpeed'] = 1.5;
        if (introCompleted == null) {
          settings.remove('introCompleted');
        } else {
          settings['introCompleted'] = introCompleted;
        }
        document['saved'] = [_title(17).toJson()];
        await store.setString(AppState.storageKey, jsonEncode(document));
        await state.initialize(discover: false);
        expect(state.prefs.introCompleted, introCompleted ?? true);
        expect(state.locale, 'fa');
        expect(state.prefs.playbackSpeed, 1.5);
        expect(state.saved.single.toJson(), _title(17).toJson());
        final persisted = jsonDecode(
          store.getString(AppState.storageKey)!,
        ) as Map<String, dynamic>;
        expect(persisted['settings']['introCompleted'], introCompleted ?? true);
        await restored.initialize(discover: false);
        expect(restored.exportLibrary(), state.exportLibrary());
      },
    );
  }

  test('settings parser defaults invalid fields without type errors', () {
    final prefs = AppSettings.fromJson({
      'locale': 'xx',
      'theme': 7,
      'autoplay': 'yes',
      'playbackSpeed': -1,
      'skipSeconds': 0,
      'subtitleFontSize': 'bad',
      'subtitleDelay': double.infinity,
      'audioDelay': null,
      'orientation': 'diagonal',
      'preferredGenres': [3, '7', null, -1, 3],
    });
    expect(prefs.locale, 'en');
    expect(prefs.theme, 'dark');
    expect(prefs.autoplay, isFalse);
    expect(prefs.playbackSpeed, 1);
    expect(prefs.skipSeconds, 10);
    expect(prefs.subtitleFontSize, 24);
    expect(prefs.subtitleDelay, 0);
    expect(prefs.audioDelay, 0);
    expect(prefs.orientation, 'auto');
    expect(prefs.preferredGenres, [3]);
    // Existing serialized settings predate onboarding and skip it on migration.
    expect(
      AppSettings.fromJson({}).toJson(),
      AppSettings(introCompleted: true).toJson(),
    );
  });
}
