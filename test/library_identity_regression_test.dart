import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const movie = TitleRecord(id: 42, title: 'Movie');
const channel = TitleRecord(id: 42, title: 'Channel', type: 'channel');

class LocalLibraryApi extends ApiService {
  @override
  Future<void> initialize({bool discover = true}) async {}
}

// Construct the old backup directly: current mutations must never save channels.
String legacyLibrary(AppState state) {
  final document = jsonDecode(state.exportLibrary()) as Map<String, dynamic>;
  document['saved'] = [channel.toJson(), movie.toJson()];
  document['history'] = [
    WatchEntry(title: channel, positionSeconds: 30).toJson(),
    WatchEntry(title: movie, positionSeconds: 15).toJson(),
  ];
  document['collections'] = [
    LocalCollection(
      id: 'both',
      name: 'Both',
      titles: [channel, movie],
    ).toJson(),
  ];
  return jsonEncode(document);
}

void expectMovieOnly(AppState state) {
  expect(state.saved.single.toJson(), movie.toJson());
  expect(state.hasSaved(42), isTrue);
  expect(state.hasSaved(42, kind: 'channel'), isFalse);
  expect(state.history.single.title.toJson(), movie.toJson());
  expect(state.resumeSeconds(42), 15);
  expect(state.resumeSeconds(42, kind: 'channel'), 0);
  expect(state.collections.single.id, 'both');
  expect(state.collections.single.name, 'Both');
  expect(state.collections.single.titles.single.toJson(), movie.toJson());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final viaStorage in [false, true]) {
    test(
      'legacy ${viaStorage ? 'storage migration' : 'import'} prunes channels without losing same-ID movies',
      () async {
        final store = await SharedPreferences.getInstance();
        final state = AppState(api: LocalLibraryApi(), storage: store);
        final restored = AppState(api: LocalLibraryApi(), storage: store);
        addTearDown(state.dispose);
        addTearDown(restored.dispose);
        final legacy = legacyLibrary(state);
        if (viaStorage) {
          await store.setString(AppState.storageKey, legacy);
          await state.initialize(discover: false);
        } else {
          await state.importLibrary(legacy);
        }
        expectMovieOnly(state);
        final sanitized = state.exportLibrary();
        expect((jsonDecode(sanitized) as Map)['version'], 1);
        expect(store.getString(AppState.storageKey), sanitized);
        await restored.initialize(discover: false);
        expectMovieOnly(restored);
        expect(restored.exportLibrary(), sanitized);
        await restored.removeSaved(42, kind: 'channel');
        await restored.removeHistory(42, kind: 'channel');
        expectMovieOnly(restored);
        await restored.removeSaved(42);
        await restored.removeHistory(42);
        expect(restored.saved, isEmpty);
        expect(restored.history, isEmpty);
        expect(
          restored.collections.single.titles.single.toJson(),
          movie.toJson(),
        );
      },
    );
  }

  test('blocked collection mutations cannot replace a same-ID movie', () async {
    final state = AppState(api: LocalLibraryApi());
    addTearDown(state.dispose);
    final collection = await state.createCollection('Both');
    await state.toggleCollectionTitle(collection.id, movie);
    final original = state.exportLibrary();
    await state.toggleCollectionTitle(collection.id, channel);
    await state.toggleCollectionTitle(collection.id, channel);
    expect(state.exportLibrary(), original);
    expect(state.collections.single.titles.single.toJson(), movie.toJson());
    await state.toggleCollectionTitle(collection.id, movie);
    await state.toggleCollectionTitle(collection.id, channel);
    expect(state.collections.single.titles, isEmpty);
  });

  test(
    'blocked history mutations cannot replace same-ID movie progress',
    () async {
      final state = AppState(api: LocalLibraryApi());
      addTearDown(state.dispose);
      await state.recordWatch(movie, positionSeconds: 15);
      final original = state.exportLibrary();
      await state.recordWatch(channel, positionSeconds: 30);
      expect(state.exportLibrary(), original);
      expect(state.history.single.title.toJson(), movie.toJson());
      expect(state.resumeSeconds(42), 15);
      expect(state.resumeSeconds(42, kind: 'channel'), 0);
      await state.removeHistory(42, kind: 'channel');
      expect(state.resumeSeconds(42), 15);
      await state.removeHistory(42);
      await state.recordWatch(channel, positionSeconds: 30);
      expect(state.history, isEmpty);
    },
  );

  test('blocked watchlist mutations cannot replace a same-ID movie', () async {
    final store = await SharedPreferences.getInstance();
    final state = AppState(api: LocalLibraryApi(), storage: store);
    addTearDown(state.dispose);
    await state.toggleSaved(movie);
    final original = state.exportLibrary();
    var notifications = 0;
    state.addListener(() => notifications++);
    await state.toggleSaved(channel);
    await state.toggleSaved(channel);
    expect(state.exportLibrary(), original);
    expect(store.getString(AppState.storageKey), original);
    expect(notifications, 0);
    expect(state.saved.single.toJson(), movie.toJson());
    expect(state.hasSaved(42), isTrue);
    expect(state.hasSaved(42, kind: 'channel'), isFalse);
    await state.removeSaved(42, kind: 'channel');
    expect(state.saved.single.toJson(), movie.toJson());
    await state.removeSaved(42);
    await state.toggleSaved(channel);
    expect(state.saved, isEmpty);
    expect(state.hasSaved(42, kind: 'channel'), isFalse);
  });

  test(
    'legacy version-one titles without type still load as posters',
    () async {
      final state = AppState(api: LocalLibraryApi());
      addTearDown(state.dispose);
      final document =
          jsonDecode(state.exportLibrary()) as Map<String, dynamic>;
      document['saved'] = [
        channel.toJson(),
        {'id': 42, 'title': 'Legacy movie'},
      ];
      await state.importLibrary(jsonEncode(document));
      expect(state.hasSaved(42), isTrue);
      expect(state.hasSaved(42, kind: 'channel'), isFalse);
      expect(state.saved.single.libraryKey, 'poster:42');
      expect(state.saved.single.title, 'Legacy movie');
      final original = state.exportLibrary();
      await state.toggleSaved(channel);
      expect(state.exportLibrary(), original);
    },
  );

  test(
    'movie and series aliases share the poster namespace during mutation',
    () async {
      final state = AppState(api: LocalLibraryApi());
      addTearDown(state.dispose);
      const series = TitleRecord(id: 42, title: 'Series', type: 'series');
      const serie = TitleRecord(id: 42, title: 'Serie', type: 'serie');
      expect(movie.libraryKey, series.libraryKey);
      expect(series.libraryKey, serie.libraryKey);
      await state.toggleSaved(series);
      expect(state.hasSaved(42, kind: 'serie'), isTrue);
      await state.toggleSaved(serie);
      expect(state.saved, isEmpty);
      await state.recordWatch(series, episodeId: 7, positionSeconds: 10);
      await state.recordWatch(serie, episodeId: 7, positionSeconds: 20);
      expect(state.history.single.positionSeconds, 20);
    },
  );

  for (final section in ['saved', 'history', 'collections']) {
    test(
      '$section rejects same-namespace duplicate imports atomically',
      () async {
        final store = await SharedPreferences.getInstance();
        final state = AppState(api: LocalLibraryApi(), storage: store);
        addTearDown(state.dispose);
        await state.toggleSaved(movie);
        final original = state.exportLibrary();
        var notifications = 0;
        state.addListener(() => notifications++);
        final document = jsonDecode(original) as Map<String, dynamic>;
        const series = TitleRecord(id: 42, title: 'Series', type: 'serie');
        if (section == 'history') {
          document[section] = [
            WatchEntry(title: channel).toJson(),
            WatchEntry(title: movie).toJson(),
            WatchEntry(title: series).toJson(),
          ];
        } else if (section == 'collections') {
          document[section] = [
            LocalCollection(
              id: 'both',
              name: 'Both',
              titles: [channel, movie, series],
            ).toJson(),
          ];
        } else {
          document[section] = [
            channel.toJson(),
            movie.toJson(),
            series.toJson(),
          ];
        }
        await expectLater(
          state.importLibrary(jsonEncode(document)),
          throwsFormatException,
        );
        expect(state.exportLibrary(), original);
        expect(store.getString(AppState.storageKey), original);
        expect(notifications, 0);
      },
    );
  }
}
