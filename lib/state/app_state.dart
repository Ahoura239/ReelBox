/// Account-free, device-local preferences and library state.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_service.dart';
import '../data/models.dart';
import '../data/content_policy.dart';

/// Movies and series share the poster endpoint; channels have their own IDs.
extension LocalTitleIdentity on TitleRecord {
  String get libraryKey => '${isChannel ? 'channel' : 'poster'}:$id';
}

String _libraryKey(int id, String kind) =>
    '${kind == 'channel' ? 'channel' : 'poster'}:$id';

class AppSettings {
  AppSettings({
    this.locale = 'en',
    this.theme = 'dark',
    this.wifiOnlyDownloads = false,
    this.autoNext = true,
    this.resumePlayback = true,
    this.autoplay = false,
    this.externalPlayer = false,
    this.defaultQuality = 'ask',
    this.playbackSpeed = 1.0,
    this.skipSeconds = 10,
    this.subtitleFontSize = 24.0,
    this.subtitleColor = 0xFFFFFFFF,
    this.subtitleBackground = 0x80000000,
    this.subtitleDelay = 0.0,
    this.audioDelay = 0.0,
    this.orientation = 'auto',
    List<int> preferredGenres = const [],
    this.hideTrailers = false,
    this.downloadNotifications = true,
    this.dataSaver = false,
    this.subtitleEnabled = true,
    this.subtitleFontFamily = 'sans-serif',
    this.videoFit = 'contain',
    this.audioOnly = false,
    this.playerVolume = 1.0,
    this.rememberVolume = false,
    this.backgroundAudio = false,
    this.closeOnCompletion = false,
    this.resumeRewindSeconds = 5,
    this.parallelDownloads = 3,
    this.compactCatalog = false,
    this.introCompleted = false,
    this.externalPlayerPackage = 'ask',
  }) : preferredGenres = List.unmodifiable(preferredGenres);

  final String locale, theme, defaultQuality, orientation;
  final bool wifiOnlyDownloads,
      autoNext,
      resumePlayback,
      autoplay,
      externalPlayer,
      hideTrailers,
      downloadNotifications,
      dataSaver;
  final double playbackSpeed, subtitleFontSize, subtitleDelay, audioDelay;
  final int skipSeconds, subtitleColor, subtitleBackground;
  final List<int> preferredGenres;
  final bool subtitleEnabled;
  final String subtitleFontFamily;
  final String videoFit;
  final bool audioOnly;
  final double playerVolume;
  final bool rememberVolume;
  final bool backgroundAudio;
  final bool closeOnCompletion;
  final int resumeRewindSeconds;
  final int parallelDownloads;
  final bool compactCatalog;
  final bool introCompleted;
  final String externalPlayerPackage;

  /// Resolve generic preferences to platform font names rather than treating
  /// CSS generic names as bundled Flutter fonts. Missing custom families still
  /// fall back through these names and Flutter's system glyph fallback.
  String? get resolvedSubtitleFontFamily {
    final apple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final android = defaultTargetPlatform == TargetPlatform.android;
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    return switch (subtitleFontFamily) {
      'sans-serif' => null, // Flutter's actual platform default.
      'serif' =>
        apple || windows
            ? 'Times New Roman'
            : android
            ? 'Noto Serif'
            : 'DejaVu Serif',
      'monospace' =>
        apple
            ? 'Menlo'
            : windows
            ? 'Consolas'
            : android
            ? 'Droid Sans Mono'
            : 'DejaVu Sans Mono',
      _ => subtitleFontFamily,
    };
  }

  List<String> get subtitleFontFamilyFallback =>
      switch (defaultTargetPlatform) {
        TargetPlatform.android => const [
          'Roboto',
          'Noto Sans Arabic',
          'Noto Naskh Arabic',
        ],
        TargetPlatform.iOS ||
        TargetPlatform.macOS => const ['Helvetica Neue', 'Arial', 'Geeza Pro'],
        TargetPlatform.windows => const ['Segoe UI', 'Arial', 'Tahoma'],
        _ => const ['DejaVu Sans', 'Noto Sans', 'Noto Sans Arabic'],
      };

  AppSettings copyWith({
    String? locale,
    String? theme,
    bool? wifiOnlyDownloads,
    bool? autoNext,
    bool? resumePlayback,
    bool? autoplay,
    bool? externalPlayer,
    String? defaultQuality,
    double? playbackSpeed,
    int? skipSeconds,
    double? subtitleFontSize,
    int? subtitleColor,
    int? subtitleBackground,
    double? subtitleDelay,
    double? audioDelay,
    String? orientation,
    List<int>? preferredGenres,
    bool? hideTrailers,
    bool? downloadNotifications,
    bool? dataSaver,
    bool? subtitleEnabled,
    String? subtitleFontFamily,
    String? videoFit,
    bool? audioOnly,
    double? playerVolume,
    bool? rememberVolume,
    bool? backgroundAudio,
    bool? closeOnCompletion,
    int? resumeRewindSeconds,
    int? parallelDownloads,
    bool? compactCatalog,
    bool? introCompleted,
    String? externalPlayerPackage,
  }) => AppSettings(
    locale: locale ?? this.locale,
    theme: theme ?? this.theme,
    wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
    autoNext: autoNext ?? this.autoNext,
    resumePlayback: resumePlayback ?? this.resumePlayback,
    autoplay: autoplay ?? this.autoplay,
    externalPlayer: externalPlayer ?? this.externalPlayer,
    defaultQuality: defaultQuality ?? this.defaultQuality,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    skipSeconds: skipSeconds ?? this.skipSeconds,
    subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
    subtitleColor: subtitleColor ?? this.subtitleColor,
    subtitleBackground: subtitleBackground ?? this.subtitleBackground,
    subtitleDelay: subtitleDelay ?? this.subtitleDelay,
    audioDelay: audioDelay ?? this.audioDelay,
    orientation: orientation ?? this.orientation,
    preferredGenres: preferredGenres ?? this.preferredGenres,
    hideTrailers: hideTrailers ?? this.hideTrailers,
    downloadNotifications: downloadNotifications ?? this.downloadNotifications,
    dataSaver: dataSaver ?? this.dataSaver,
    subtitleEnabled: subtitleEnabled ?? this.subtitleEnabled,
    subtitleFontFamily: subtitleFontFamily ?? this.subtitleFontFamily,
    videoFit: videoFit ?? this.videoFit,
    audioOnly: audioOnly ?? this.audioOnly,
    playerVolume: playerVolume ?? this.playerVolume,
    rememberVolume: rememberVolume ?? this.rememberVolume,
    backgroundAudio: backgroundAudio ?? this.backgroundAudio,
    closeOnCompletion: closeOnCompletion ?? this.closeOnCompletion,
    resumeRewindSeconds: resumeRewindSeconds ?? this.resumeRewindSeconds,
    parallelDownloads: parallelDownloads ?? this.parallelDownloads,
    compactCatalog: compactCatalog ?? this.compactCatalog,
    introCompleted: introCompleted ?? this.introCompleted,
    externalPlayerPackage: externalPlayerPackage ?? this.externalPlayerPackage,
  );

  Map<String, dynamic> toJson() => {
    'locale': locale,
    'theme': theme,
    'wifiOnlyDownloads': wifiOnlyDownloads,
    'autoNext': autoNext,
    'resumePlayback': resumePlayback,
    'autoplay': autoplay,
    'externalPlayer': externalPlayer,
    'defaultQuality': defaultQuality,
    'playbackSpeed': playbackSpeed,
    'skipSeconds': skipSeconds,
    'subtitleFontSize': subtitleFontSize,
    'subtitleColor': subtitleColor,
    'subtitleBackground': subtitleBackground,
    'subtitleDelay': subtitleDelay,
    'audioDelay': audioDelay,
    'orientation': orientation,
    'preferredGenres': preferredGenres,
    'hideTrailers': hideTrailers,
    'downloadNotifications': downloadNotifications,
    'dataSaver': dataSaver,
    'subtitleEnabled': subtitleEnabled,
    'subtitleFontFamily': subtitleFontFamily,
    'videoFit': videoFit,
    'audioOnly': audioOnly,
    'playerVolume': playerVolume,
    'rememberVolume': rememberVolume,
    'backgroundAudio': backgroundAudio,
    'closeOnCompletion': closeOnCompletion,
    'resumeRewindSeconds': resumeRewindSeconds,
    'parallelDownloads': parallelDownloads,
    'compactCatalog': compactCatalog,
    'introCompleted': introCompleted,
    'externalPlayerPackage': externalPlayerPackage,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    bool boolean(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    String choice(String key, Set<String> allowed, String fallback) =>
        allowed.contains(json[key]) ? json[key] as String : fallback;
    double number(String key, double fallback, {double? min, double? max}) {
      final value = json[key];
      if (value is! num ||
          !value.isFinite ||
          (min != null && value < min) ||
          (max != null && value > max)) {
        return fallback;
      }
      return value.toDouble();
    }

    int integer(String key, int fallback, int min, int max) {
      final value = json[key];
      return value is int && value >= min && value <= max ? value : fallback;
    }

    String safeString(String key, String fallback, {bool package = false}) {
      final value = json[key];
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > 120 ||
          !ContentPolicy.allowsText(value) ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
          (package &&
              value != 'ask' &&
              !RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')
                  .hasMatch(value))) {
        return fallback;
      }
      return value.trim();
    }

    final genres = json['preferredGenres'];
    return AppSettings(
      locale: choice('locale', {'en', 'fa'}, 'en'),
      theme: choice('theme', {'dark', 'light', 'system'}, 'dark'),
      wifiOnlyDownloads: boolean('wifiOnlyDownloads', false),
      autoNext: boolean('autoNext', true),
      resumePlayback: boolean('resumePlayback', true),
      autoplay: boolean('autoplay', false),
      externalPlayer: boolean('externalPlayer', false),
      defaultQuality: safeString('defaultQuality', 'ask'),
      playbackSpeed: number('playbackSpeed', 1, min: 0.25, max: 4),
      skipSeconds: integer('skipSeconds', 10, 1, 600),
      subtitleFontSize: number('subtitleFontSize', 24, min: 8, max: 96),
      subtitleColor: integer('subtitleColor', 0xFFFFFFFF, 0, 0xFFFFFFFF),
      subtitleBackground: integer(
        'subtitleBackground',
        0x80000000,
        0,
        0xFFFFFFFF,
      ),
      subtitleDelay: number('subtitleDelay', 0, min: -60, max: 60),
      audioDelay: number('audioDelay', 0, min: -60, max: 60),
      orientation: choice('orientation', {
        'auto',
        'portrait',
        'landscape',
      }, 'auto'),
      preferredGenres: genres is List
          ? genres.whereType<int>().where((id) => id > 0).toSet().toList()
          : const [],
      hideTrailers: boolean('hideTrailers', false),
      downloadNotifications: boolean('downloadNotifications', true),
      dataSaver: boolean('dataSaver', false),
      subtitleEnabled: boolean('subtitleEnabled', true),
      subtitleFontFamily: safeString('subtitleFontFamily', 'sans-serif'),
      videoFit: choice('videoFit', {'contain', 'cover', 'fill'}, 'contain'),
      audioOnly: boolean('audioOnly', false),
      playerVolume: number('playerVolume', 1, min: 0, max: 1),
      rememberVolume: boolean('rememberVolume', false),
      backgroundAudio: boolean('backgroundAudio', false),
      closeOnCompletion: boolean('closeOnCompletion', false),
      resumeRewindSeconds: integer('resumeRewindSeconds', 5, 0, 120),
      parallelDownloads: integer('parallelDownloads', 3, 1, 8),
      compactCatalog: boolean('compactCatalog', false),
      introCompleted: boolean('introCompleted', true),
      externalPlayerPackage: safeString(
        'externalPlayerPackage',
        'ask',
        package: true,
      ),
    );
  }
}

class WatchEntry {
  WatchEntry({
    required this.title,
    this.episodeId,
    this.episodeTitle = '',
    this.sourceUrl = '',
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    DateTime? updatedAt,
  }) : updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  final TitleRecord title;
  final int? episodeId;
  final String episodeTitle, sourceUrl;
  final double positionSeconds, durationSeconds;
  final DateTime updatedAt;

  double get progress =>
      durationSeconds > 0 &&
          durationSeconds.isFinite &&
          positionSeconds.isFinite
      ? (positionSeconds / durationSeconds).clamp(0.0, 1.0)
      : 0;

  Map<String, dynamic> toJson() => {
    'title': title.toJson(),
    'episodeId': episodeId,
    'episodeTitle': episodeTitle,
    'sourceUrl': sourceUrl,
    'positionSeconds': positionSeconds,
    'durationSeconds': durationSeconds,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory WatchEntry.fromJson(Map<String, dynamic> json) {
    final episode = json['episodeId'];
    final position = json['positionSeconds'];
    final duration = json['durationSeconds'];
    final timestamp = json['updatedAt'];
    final date = timestamp is String ? DateTime.tryParse(timestamp) : null;
    if ((episode != null && (episode is! int || episode <= 0)) ||
        json['episodeTitle'] is! String ||
        json['sourceUrl'] is! String ||
        position is! num ||
        !position.isFinite ||
        position < 0 ||
        duration is! num ||
        !duration.isFinite ||
        duration < 0 ||
        date == null) {
      throw const FormatException('Invalid watch entry');
    }
    return WatchEntry(
      title: _parseTitles([json['title']]).single,
      episodeId: episode as int?,
      episodeTitle: ContentPolicy.sanitizeText(json['episodeTitle'] as String),
      sourceUrl: ContentPolicy.allowsUrl(json['sourceUrl'] as String)
          ? json['sourceUrl'] as String
          : '',
      positionSeconds: position.toDouble(),
      durationSeconds: duration.toDouble(),
      updatedAt: date,
    );
  }
}

class LocalCollection {
  LocalCollection({
    required this.id,
    required this.name,
    List<TitleRecord> titles = const [],
  }) : titles = List.unmodifiable(titles);

  final String id, name;
  final List<TitleRecord> titles;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'titles': titles.map((title) => title.toJson()).toList(),
  };

  factory LocalCollection.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty) {
      throw const FormatException('Invalid local collection');
    }
    return LocalCollection(
      id: id,
      name: ContentPolicy.allowsText(name) ? name : 'Local collection',
      titles: _parseTitles(json['titles']),
    );
  }
}

bool _allowsPersistedTitle(Map<String, dynamic> json) =>
    json['type'] != 'channel' &&
    json['kind'] != 'channel' &&
    ContentPolicy.allowsTitleJson(json);

/// A deliberate completion marker, not a playback position.
class EpisodeWatchMarker {
  const EpisodeWatchMarker({
    required this.title,
    required this.episodeId,
    this.episodeTitle = '',
  });
  final TitleRecord title;
  final int episodeId;
  final String episodeTitle;
  Map<String, dynamic> toJson() => {
    'title': title.toJson(),
    'episodeId': episodeId,
    'episodeTitle': episodeTitle,
  };
}

List<EpisodeWatchMarker> _parseMarkers(dynamic value) {
  if (value == null) return const []; // Backward-compatible v1 extension.
  if (value is! List) {
    throw const FormatException('Expected watched episode markers');
  }
  final seen = <String>{};
  final result = <EpisodeWatchMarker>[];
  for (final item in value) {
    final json = _object(item);
    final titleJson = _object(json['title']);
    if (!_allowsPersistedTitle(titleJson)) continue;
    final title = _parseTitles([titleJson]).single;
    final episodeId = json['episodeId'];
    if (episodeId is! int ||
        episodeId <= 0 ||
        json['episodeTitle'] is! String ||
        !seen.add('${title.libraryKey}:$episodeId')) {
      throw const FormatException(
        'Invalid or duplicate watched episode marker',
      );
    }
    result.add(
      EpisodeWatchMarker(
        title: title,
        episodeId: episodeId,
        episodeTitle: ContentPolicy.sanitizeText(
          json['episodeTitle'] as String,
        ),
      ),
    );
  }
  return result;
}

class HistoryContinuation {
  const HistoryContinuation({
    required this.title,
    required this.source,
    this.episode,
    this.playlist = const [],
    this.alternatives = const [],
  });
  final TitleRecord title;
  final MediaSource source;
  final EpisodeRecord? episode;
  final List<EpisodeRecord> playlist;
  final List<MediaSource> alternatives;
}

class _Library {
  _Library({
    AppSettings? prefs,
    List<TitleRecord> saved = const [],
    List<WatchEntry> history = const [],
    List<String> searchHistory = const [],
    List<LocalCollection> collections = const [],
    List<EpisodeWatchMarker> watchedEpisodes = const [],
  }) : prefs = prefs ?? AppSettings(),
       saved = List.unmodifiable(saved),
       history = List.unmodifiable(history),
       searchHistory = List.unmodifiable(searchHistory),
       collections = List.unmodifiable(collections),
       watchedEpisodes = List.unmodifiable(watchedEpisodes);

  final AppSettings prefs;
  final List<TitleRecord> saved;
  final List<WatchEntry> history;
  final List<String> searchHistory;
  final List<LocalCollection> collections;
  final List<EpisodeWatchMarker> watchedEpisodes;

  _Library copyWith({
    AppSettings? prefs,
    List<TitleRecord>? saved,
    List<WatchEntry>? history,
    List<String>? searchHistory,
    List<LocalCollection>? collections,
    List<EpisodeWatchMarker>? watchedEpisodes,
  }) => _Library(
    prefs: prefs ?? this.prefs,
    saved: saved ?? this.saved,
    history: history ?? this.history,
    searchHistory: searchHistory ?? this.searchHistory,
    collections: collections ?? this.collections,
    watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
  );

  Map<String, dynamic> toJson() => {
    'format': 'reelbox.library',
    'version': 1,
    'settings': prefs.toJson(),
    'saved': saved.map((title) => title.toJson()).toList(),
    'history': history.map((entry) => entry.toJson()).toList(),
    'searchHistory': searchHistory,
    'collections': collections.map((item) => item.toJson()).toList(),
    'watchedEpisodes': watchedEpisodes.map((item) => item.toJson()).toList(),
  };

  factory _Library.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'reelbox.library' ||
        json['version'] != 1 ||
        json['version'] is! int) {
      throw const FormatException('Unsupported Reelbox library format/version');
    }
    final titles = _parseTitles(json['saved']);
    final watch = json['history'];
    if (watch is! List) throw const FormatException('Expected watch history');
    final entries = watch
        .where(
          (value) => _allowsPersistedTitle(_object(_object(value)['title'])),
        )
        .map((value) => WatchEntry.fromJson(_object(value)))
        .toList();
    final keys = <String>{};
    for (final entry in entries) {
      if (!keys.add('${entry.title.libraryKey}:${entry.episodeId}')) {
        throw const FormatException('Duplicate watch entry');
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final rawCollections = json['collections'];
    if (rawCollections is! List) {
      throw const FormatException('Expected local collections');
    }
    final collections = rawCollections
        .map((item) => LocalCollection.fromJson(_object(item)))
        .toList();
    final collectionIds = <String>{};
    if (collections.any((item) => !collectionIds.add(item.id))) {
      throw const FormatException('Duplicate local collection ID');
    }
    return _Library(
      prefs: AppSettings.fromJson(_object(json['settings'])),
      saved: titles,
      history: entries.take(1000).toList(),
      searchHistory: _parseSearchHistory(json['searchHistory']),
      collections: collections,
      watchedEpisodes: _parseMarkers(json['watchedEpisodes']),
    );
  }
}

List<String> _parseSearchHistory(dynamic value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Expected search history strings');
  }
  final seen = <String>{};
  return value
      .cast<String>()
      .map((item) => item.trim())
      .where(
        (item) =>
            item.isNotEmpty &&
            ContentPolicy.allowsText(item) &&
            seen.add(item.toLowerCase()),
      )
      .take(30)
      .toList();
}

Map<String, dynamic> _object(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object');
  }
  return value;
}

List<TitleRecord> _parseTitles(dynamic value) {
  if (value is! List) throw const FormatException('Expected a title list');
  final ids = <String>{};
  return value
      .where((item) => _allowsPersistedTitle(_object(item)))
      .map((item) {
        final json = _object(item);
        final id = json['id'];
        if (id is! int || id <= 0 || json['title'] is! String) {
          throw const FormatException('Invalid or duplicate title');
        }
        final title = TitleRecord.fromJson(json);
        if (!ids.add(title.libraryKey)) {
          throw const FormatException('Invalid or duplicate title');
        }
        return title;
      })
      .where((title) => _allowsPersistedTitle(title.toJson()))
      .toList();
}

/// All mutations are queued, durably written as one versioned JSON value, then
/// published. Await returned futures to surface storage and validation errors.
class AppState extends ChangeNotifier {
  AppState({ApiService? api, this._storage}) : api = api ?? ApiService();

  static const storageKey = 'reelbox.local.library.v1';
  final ApiService api;
  SharedPreferences? _storage;
  _Library _data = _Library();
  Future<void> _pending = Future.value();
  bool _loaded = false;
  bool _disposed = false;
  bool _initialized = false;

  AppSettings get prefs => _data.prefs;
  String get locale => prefs.locale;
  List<int> get selectedGenres => prefs.preferredGenres;
  List<TitleRecord> get saved => _data.saved;
  List<WatchEntry> get history => _data.history;
  List<String> get searchHistory => _data.searchHistory;
  List<LocalCollection> get collections => _data.collections;

  /// Legacy integer-only callers refer to the poster namespace.
  bool hasSaved(int id, {String kind = 'poster'}) =>
      saved.any((title) => title.libraryKey == _libraryKey(id, kind));

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _pending.then((_) {
      if (_disposed) throw StateError('AppState is disposed');
      return action();
    });
    // A failed caller-visible operation must not poison later operations.
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _load() async {
    if (_loaded) return;
    final storage = _storage ??= await SharedPreferences.getInstance();
    final encoded = storage.getString(storageKey);
    if (encoded != null) {
      final migrated = _Library.fromJson(_object(jsonDecode(encoded)));
      final sanitized = jsonEncode(migrated.toJson());
      // Retain the same v1 namespace and all allowed user data. Do not reset a
      // failed/corrupt load; surface errors and keep its original backup intact.
      if (sanitized != encoded &&
          !await storage.setString(storageKey, sanitized)) {
        throw StateError('Could not persist the local library migration');
      }
      _data = migrated;
    }
    _loaded = true;
  }

  Future<void> initialize({bool discover = true}) => _enqueue(() async {
    if (_initialized) return;
    await _load();
    await api.initialize(discover: discover);
    _initialized = true;
    if (!_disposed) notifyListeners();
  });

  Future<void> _commit(_Library next) async {
    final safeNext = _Library.fromJson(next.toJson());
    final encoded = jsonEncode(safeNext.toJson());
    final success = await _storage!.setString(storageKey, encoded);
    if (!success) {
      throw StateError('Could not persist the local Reelbox library');
    }
    _data = safeNext;
    if (!_disposed) notifyListeners();
  }

  Future<void> toggleSaved(TitleRecord title) => _enqueue(() async {
    await _load();
    if (!_allowsPersistedTitle(title.toJson())) return;
    if (title.id <= 0) throw ArgumentError.value(title.id, 'title.id');
    await _commit(
      _data.copyWith(
        saved: hasSaved(title.id, kind: title.type)
            ? saved
                  .where((item) => item.libraryKey != title.libraryKey)
                  .toList()
            : [title, ...saved],
      ),
    );
  });

  Future<void> removeSaved(int id, {String kind = 'poster'}) =>
      _enqueue(() async {
        await _load();
        await _commit(
          _data.copyWith(
            saved: saved
                .where((title) => title.libraryKey != _libraryKey(id, kind))
                .toList(),
          ),
        );
      });

  Future<void> updateSettings(AppSettings settings) => _enqueue(() async {
    await _load();
    await _commit(
      _data.copyWith(prefs: AppSettings.fromJson(settings.toJson())),
    );
  });

  Future<void> rememberSearch(String query) => _enqueue(() async {
    await _load();
    final text = query.trim();
    if (text.isEmpty || !ContentPolicy.allowsText(text)) return;
    await _commit(
      _data.copyWith(
        searchHistory: [
          text,
          ...searchHistory.where(
            (item) => item.toLowerCase() != text.toLowerCase(),
          ),
        ].take(30).toList(),
      ),
    );
  });

  Future<void> removeSearch(String query) => _enqueue(() async {
    await _load();
    final key = query.trim().toLowerCase();
    await _commit(
      _data.copyWith(
        searchHistory: searchHistory
            .where((item) => item.toLowerCase() != key)
            .toList(),
      ),
    );
  });

  Future<void> clearSearchHistory() => _enqueue(() async {
    await _load();
    await _commit(_data.copyWith(searchHistory: []));
  });

  Future<void> recordWatch(
    TitleRecord title, {
    int? episodeId,
    String episodeTitle = '',
    String sourceUrl = '',
    double positionSeconds = 0,
    double durationSeconds = 0,
  }) => _enqueue(() async {
    await _load();
    if (title.id <= 0 ||
        (episodeId != null && episodeId <= 0) ||
        !positionSeconds.isFinite ||
        positionSeconds < 0 ||
        !durationSeconds.isFinite ||
        durationSeconds < 0) {
      throw ArgumentError(
        'Watch IDs and positions must be valid and non-negative',
      );
    }
    if (!_allowsPersistedTitle(title.toJson())) return;
    final entry = WatchEntry(
      title: title,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
      sourceUrl: sourceUrl,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
    );
    await _commit(
      _data.copyWith(
        history: [
          entry,
          ...history.where(
            (item) =>
                item.title.libraryKey != title.libraryKey ||
                item.episodeId != episodeId,
          ),
        ].take(1000).toList(),
      ),
    );
  });

  double resumeSeconds(int titleId, {int? episodeId, String kind = 'poster'}) {
    if (!prefs.resumePlayback) return 0;
    for (final entry in history) {
      if (entry.title.libraryKey == _libraryKey(titleId, kind) &&
          entry.episodeId == episodeId) {
        return entry.positionSeconds;
      }
    }
    return 0;
  }

  /// Removes only the exact namespace/title/episode tuple.
  /// Legacy callers default to posters; null identifies a non-episode entry.
  Future<void> removeHistory(
    int titleId, {
    int? episodeId,
    String kind = 'poster',
  }) => _enqueue(() async {
    await _load();
    await _commit(
      _data.copyWith(
        history: history
            .where(
              (entry) =>
                  entry.title.libraryKey != _libraryKey(titleId, kind) ||
                  entry.episodeId != episodeId,
            )
            .toList(),
      ),
    );
  });

  Future<void> clearHistory() => _enqueue(() async {
    await _load();
    await _commit(_data.copyWith(history: []));
  });

  Future<LocalCollection> createCollection(String name) => _enqueue(() async {
    await _load();
    final text = name.trim();
    if (text.isEmpty || !ContentPolicy.allowsText(text)) {
      throw ArgumentError('A valid local collection name is required');
    }
    final base = 'local-${DateTime.now().microsecondsSinceEpoch}';
    var id = base;
    var suffix = 0;
    while (collections.any((item) => item.id == id)) {
      id = '$base-${++suffix}';
    }
    final collection = LocalCollection(id: id, name: text);
    await _commit(_data.copyWith(collections: [...collections, collection]));
    return collection;
  });

  Future<void> deleteCollection(String collectionId) => _enqueue(() async {
    await _load();
    await _commit(
      _data.copyWith(
        collections: collections
            .where((item) => item.id != collectionId)
            .toList(),
      ),
    );
  });

  Future<void> toggleCollectionTitle(String collectionId, TitleRecord title) =>
      _enqueue(() async {
        await _load();
        if (!_allowsPersistedTitle(title.toJson())) return;
        if (title.id <= 0) throw ArgumentError.value(title.id, 'title.id');
        final index = collections.indexWhere((item) => item.id == collectionId);
        if (index < 0) throw StateError('Local collection not found');
        final collection = collections[index];
        final hasTitle = collection.titles.any(
          (item) => item.libraryKey == title.libraryKey,
        );
        final updated = LocalCollection(
          id: collection.id,
          name: collection.name,
          titles: hasTitle
              ? collection.titles
                    .where((item) => item.libraryKey != title.libraryKey)
                    .toList()
              : [...collection.titles, title],
        );
        final next = [...collections];
        next[index] = updated;
        await _commit(_data.copyWith(collections: next));
      });

  int get savedCount => saved.length;
  int get historyCount => history.length;
  int get collectionCount => collections.length;
  int get watchedEpisodeCount => _data.watchedEpisodes.length;
  List<EpisodeWatchMarker> get watchedEpisodes => _data.watchedEpisodes;

  bool isEpisodeWatched(int titleId, int episodeId) =>
      _data.watchedEpisodes.any(
        (entry) => entry.title.id == titleId && entry.episodeId == episodeId,
      );

  Future<void> setEpisodeWatched(
    TitleRecord title,
    EpisodeRecord episode,
    bool watched,
  ) => _enqueue(() async {
    await _load();
    if (!_allowsPersistedTitle(title.toJson())) return;
    if (title.id <= 0 || episode.id <= 0) {
      throw ArgumentError('Positive title and episode IDs are required');
    }
    final next = _data.watchedEpisodes
        .where(
          (entry) =>
              entry.title.libraryKey != title.libraryKey ||
              entry.episodeId != episode.id,
        )
        .toList();
    if (watched) {
      next.add(
        EpisodeWatchMarker(
          title: title,
          episodeId: episode.id,
          episodeTitle: ContentPolicy.sanitizeText(episode.title),
        ),
      );
    }
    await _commit(_data.copyWith(watchedEpisodes: next));
  });

  /// Does not touch audio delay, playback preferences, downloads or the library.
  Future<void> resetSubtitleStyle() => _enqueue(() async {
    await _load();
    await _commit(
      _data.copyWith(
        prefs: prefs.copyWith(
          subtitleEnabled: true,
          subtitleFontFamily: 'sans-serif',
          subtitleFontSize: 24,
          subtitleColor: 0xFFFFFFFF,
          subtitleBackground: 0x80000000,
          subtitleDelay: 0,
        ),
      ),
    );
  });

  /// Stored source URLs can expire. Always fetch current metadata before playing.
  Future<HistoryContinuation> resolveHistory(WatchEntry entry) async {
    if (!_allowsPersistedTitle(entry.title.toJson())) {
      throw StateError('This title is no longer available');
    }
    final title = await api.poster(entry.title.id);
    if (!_allowsPersistedTitle(title.toJson())) {
      throw StateError('This title is no longer available');
    }
    EpisodeRecord? episode;
    List<EpisodeRecord> playlist = const [];
    if (entry.episodeId != null) {
      playlist = (await api.seasons(title.id))
          .expand((season) => season.episodes)
          .toList();
      final matches = playlist.where((item) => item.id == entry.episodeId);
      if (matches.isEmpty) {
        throw StateError('This episode is no longer available');
      }
      episode = matches.first;
    }
    final sources = (episode?.sources ?? title.sources).where((source) {
      final uri = Uri.tryParse(source.url);
      return uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          ContentPolicy.allowsUrl(source.url) &&
          (!prefs.hideTrailers || !source.isTrailer);
    }).toList();
    if (sources.isEmpty) {
      throw StateError('No current playable sources. Open the title to retry.');
    }
    final preferred = sources.where(
      (source) =>
          source.url == entry.sourceUrl ||
          (prefs.defaultQuality != 'ask' &&
              prefs.defaultQuality != 'auto' &&
              source.quality.contains(prefs.defaultQuality)),
    );
    return HistoryContinuation(
      title: title,
      source: preferred.firstOrNull ?? sources.first,
      episode: episode,
      playlist: playlist,
      alternatives: sources,
    );
  }

  String exportLibrary() => jsonEncode(_data.toJson());

  Future<void> importLibrary(String text) => _enqueue(() async {
    if (utf8.encode(text).length > 8 * 1024 * 1024) {
      throw const FormatException('Library backup exceeds 8 MB');
    }
    final next = _Library.fromJson(_object(jsonDecode(text)));
    await _load();
    await _commit(next);
  });

  Future<void> clearLocalData() => _enqueue(() async {
    await _load();
    await _commit(_Library());
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    AppState? state,
    AppState? notifier,
    required super.child,
  }) : assert(state != null || notifier != null),
       super(notifier: state ?? notifier);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope?.notifier == null) throw StateError('AppScope is missing');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    if (scope?.notifier == null) throw StateError('AppScope is missing');
    return scope!.notifier!;
  }
}

String tr(BuildContext context, String english, String persian) =>
    AppScope.of(context).locale == 'fa' ? persian : english;
