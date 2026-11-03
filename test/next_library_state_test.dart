import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/api_service.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const movie = TitleRecord(id: 8, title: 'A film');
const episode = EpisodeRecord(id: 12, title: 'Part 1');

class LocalApi extends ApiService {
  @override
  Future<void> initialize({bool discover = true}) async {}
  @override
  Future<TitleRecord> poster(int id) async => const TitleRecord(
    id: 8,
    title: 'Current film',
    image: 'https://example.org/current.jpg',
    sources: [MediaSource(id: 2, url: 'https://example.org/new.mp4')],
  );
  @override
  Future<List<SeasonRecord>> seasons(int id) async => const [
    SeasonRecord(
      id: 1,
      episodes: [
        EpisodeRecord(
          id: 12,
          title: 'Current episode',
          sources: [
            MediaSource(id: 3, url: 'https://example.org/episode-new.mp4'),
          ],
        ),
      ],
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('legacy migration filters blocked raw records before validation and persists safe state', () async {
    final store = await SharedPreferences.getInstance();
    final legacy = {
      'format': 'reelbox.library',
      'version': 1,
      'settings': {'locale': 'fa'},
      'saved': [
        movie.toJson(),
        {'id': -1, 'type': 'channel'},
        {'id': 0, 'title': 'Norton'},
      ],
      'history': <dynamic>[],
      'searchHistory': <dynamic>[],
      'collections': [
        {
          'id': 'private-id',
          'name': 'Private name',
          'titles': [
            movie.toJson(),
            {'title': 'ملودی باکس'},
          ],
        },
      ],
    };
    await store.setString(AppState.storageKey, jsonEncode(legacy));
    final state = AppState(api: LocalApi());
    await state.initialize(discover: false);
    expect(state.prefs.introCompleted, true);
    expect(state.saved.single.id, 8);
    expect(state.collections.single.id, 'private-id');
    expect(state.collections.single.name, 'Private name');
    expect(state.collections.single.titles.single.id, 8);
    final persisted = jsonDecode(store.getString(AppState.storageKey)!);
    expect(persisted['saved'].length, 1);
    expect(persisted['collections'][0]['titles'].length, 1);
    state.dispose();
  });

  test(
    'free-form local labels and settings cannot surface excluded promotions',
    () async {
      final state = AppState(api: LocalApi());
      await expectLater(state.createCollection('Norton'), throwsArgumentError);
      await state.updateSettings(
        state.prefs.copyWith(
          subtitleFontFamily: 'ملودی باکس',
          defaultQuality: 'https://t.me/example',
        ),
      );
      expect(state.prefs.subtitleFontFamily, 'sans-serif');
      expect(state.prefs.defaultQuality, 'ask');
      final collection = await state.createCollection('Keep me');
      await state.toggleCollectionTitle(collection.id, movie);
      final backup = jsonDecode(state.exportLibrary()) as Map<String, dynamic>;
      backup['collections'][0]['name'] = 'Norton';
      await state.importLibrary(jsonEncode(backup));
      expect(state.collections.single.name, 'Local collection');
      expect(state.collections.single.titles.single.id, movie.id);
      state.dispose();
    },
  );

  test('malformed backup and failed startup never reset an existing private library', () async {
    final state = AppState(api: LocalApi());
    await state.toggleSaved(movie);
    final before = state.exportLibrary();
    final malformed = jsonDecode(before) as Map<String, dynamic>;
    malformed['watchedEpisodes'] = [
      {'title': movie.toJson(), 'episodeId': -1, 'episodeTitle': ''},
    ];
    await expectLater(
      state.importLibrary(jsonEncode(malformed)),
      throwsFormatException,
    );
    expect(state.exportLibrary(), before);
    final store = await SharedPreferences.getInstance();
    const corrupt = '{not valid JSON';
    await store.setString(AppState.storageKey, corrupt);
    final restored = AppState(api: LocalApi());
    await expectLater(
      restored.initialize(discover: false),
      throwsFormatException,
    );
    expect(store.getString(AppState.storageKey), corrupt);
    state.dispose();
    restored.dispose();
  });

  test(
    'episode watched marker persists without fabricating playback checkpoints',
    () async {
      final state = AppState(api: LocalApi());
      await state.setEpisodeWatched(movie, episode, true);
      expect(state.isEpisodeWatched(8, 12), true);
      expect(state.history, isEmpty);
      await state.recordWatch(movie, episodeId: 12, positionSeconds: 24);
      await state.setEpisodeWatched(movie, episode, false);
      expect(state.isEpisodeWatched(8, 12), false);
      expect(state.resumeSeconds(8, episodeId: 12), 24);
      await state.setEpisodeWatched(movie, episode, true);
      final restored = AppState(api: LocalApi());
      await restored.initialize(discover: false);
      expect(restored.isEpisodeWatched(8, 12), true);
      final imported = AppState(api: LocalApi());
      await imported.importLibrary(state.exportLibrary());
      expect(imported.isEpisodeWatched(8, 12), true);
      state.dispose();
      restored.dispose();
      imported.dispose();
    },
  );

  test(
    'subtitle reset changes only subtitle fields and preserves local library',
    () async {
      final state = AppState(api: LocalApi());
      await state.toggleSaved(movie);
      await state.createCollection('Private');
      await state.updateSettings(
        state.prefs.copyWith(
          locale: 'fa',
          parallelDownloads: 7,
          subtitleFontSize: 60,
          subtitleColor: 0x12123456,
          subtitleDelay: 4,
          subtitleFontFamily: 'serif',
          subtitleEnabled: false,
          audioDelay: 2,
        ),
      );
      await state.resetSubtitleStyle();
      expect(state.prefs.subtitleFontSize, 24);
      expect(state.prefs.subtitleColor, 0xFFFFFFFF);
      expect(state.prefs.subtitleFontFamily, 'sans-serif');
      expect(state.prefs.subtitleDelay, 0);
      expect(state.prefs.subtitleEnabled, true);
      expect(state.prefs.audioDelay, 2);
      expect(state.prefs.parallelDownloads, 7);
      expect(state.locale, 'fa');
      expect(state.saved.single.id, 8);
      expect(state.collections.single.name, 'Private');
      state.dispose();
    },
  );

  test('missing current episode rejects continuation instead of playing an expired checkpoint URL', () async {
    final state = AppState(api: LocalApi());
    await state.recordWatch(
      movie,
      episodeId: 404,
      sourceUrl: 'https://example.org/expired.mp4',
      positionSeconds: 99,
    );
    await expectLater(
      state.resolveHistory(state.history.single),
      throwsStateError,
    );
    expect(state.resumeSeconds(8, episodeId: 404), 99);
    state.dispose();
  });

  test(
    'continuation resolves fresh poster and episode sources, never stale URL',
    () async {
      final state = AppState(api: LocalApi());
      await state.recordWatch(
        movie,
        episodeId: 12,
        sourceUrl: 'https://example.org/expired.mp4',
        positionSeconds: 24,
      );
      final continuation = await state.resolveHistory(state.history.single);
      expect(continuation.title.image, 'https://example.org/current.jpg');
      expect(continuation.source.url, 'https://example.org/episode-new.mp4');
      expect(continuation.episode?.id, 12);
      expect(continuation.playlist.single.id, 12);
      state.dispose();
    },
  );

  test('legacy import retains private collections while removing blocked titles/channels', () async {
    final state = AppState(api: LocalApi());
    await state.toggleSaved(movie);
    final collection = await state.createCollection('Private');
    await state.toggleCollectionTitle(collection.id, movie);
    final backup = jsonDecode(state.exportLibrary()) as Map<String, dynamic>;
    backup['saved'].add(
      const TitleRecord(id: 9, type: 'channel', title: 'Channel').toJson(),
    );
    backup['saved'].add(
      const TitleRecord(id: 10, title: 'ملودی باکس').toJson(),
    );
    backup['collections'][0]['titles'].add(
      const TitleRecord(id: 11, title: 'Norton').toJson(),
    );
    await state.importLibrary(jsonEncode(backup));
    expect(state.saved.map((t) => t.id), [8]);
    expect(state.collections.single.titles.map((t) => t.id), [8]);
    await state.toggleSaved(const TitleRecord(id: 10, title: 'ملودی باکس'));
    expect(state.saved.length, 1);
    state.dispose();
  });
}
