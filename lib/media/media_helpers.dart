import 'dart:convert';

import 'package:media_kit/media_kit.dart';

import '../data/models.dart';
import '../state/app_state.dart';

/// Orchestrates pending player work across route disposal/source changes.
class PlaybackLifecycle {
  PlaybackLifecycle({this.isMounted});
  final bool Function()? isMounted;
  bool _disposed = false;
  int _openGeneration = 0;
  // Platform/window state is shared by every player route, not just a widget.
  static Future<void>? _systemTail;
  static PlaybackLifecycle? _systemOwner;
  bool get ownsSystem => _active && identical(_systemOwner, this);
  bool get _active => !_disposed && (isMounted?.call() ?? true);

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final previous = _systemTail;
    // Drop completed futures when idle, rather than keeping a previous player's
    // scheduling zone alive. Work is still serialized across active routes.
    final work = previous == null
        ? Future<T>.microtask(action)
        : previous.then((_) => action());
    late final Future<void> tail;
    tail = work
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          if (identical(_systemTail, tail)) _systemTail = null;
        });
    _systemTail = tail;
    return work;
  }

  Future<bool> setup(List<Future<void> Function()> steps) {
    // Capture ownership before even awaiting the system-work queue.
    final activeAtStart = _active;
    return _serialize(() async {
      if (!activeAtStart || !_active) return false;
      _systemOwner = this;
      for (final step in steps) {
        await step();
        if (!_active) return false;
      }
      return true;
    });
  }

  Future<bool> open({
    required Future<void> Function() save,
    required Future<void> Function(bool Function() current) dispatch,
  }) async {
    final generation = ++_openGeneration;
    bool current() => _active && generation == _openGeneration;
    if (!current()) return false;
    await save();
    if (!current()) return false;
    await dispatch(current);
    return current();
  }

  Future<void> dispose(Future<void> Function() restore) {
    _disposed = true;
    _openGeneration++;
    // A previous route must never restore global state over a newer owner.
    return _serialize(() async {
      if (!identical(_systemOwner, this)) return;
      await restore();
      if (identical(_systemOwner, this)) _systemOwner = null;
    });
  }
}

Future<void> dispatchMediaOpen({
  required Future<void> Function(Media media, {bool play}) open,
  required String uri,
  required Duration start,
  required bool autoplay,
}) => open(Media(uri, start: start), play: autoplay);

/// Keep startup/failed-open zero state out of durable resume history.
class PlaybackCheckpoint {
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool _opened = false;
  bool get canPersist => _opened && position > Duration.zero;
  void beginOpen() {
    _opened = false;
    position = Duration.zero;
    duration = Duration.zero;
  }

  void didOpen() {
    _opened = true;
  }
}

EpisodeRecord? nextEpisode(List<EpisodeRecord> episodes, int? currentId) {
  final index = episodes.indexWhere((episode) => episode.id == currentId);
  return index >= 0 && index + 1 < episodes.length ? episodes[index + 1] : null;
}

String watchKey(int titleId, int? episodeId) =>
    '$titleId:${episodeId ?? 'movie'}';

Duration resumePosition({
  required Duration position,
  required Duration duration,
  int rewindSeconds = 0,
}) {
  if (position < const Duration(seconds: 5)) return Duration.zero;
  if (duration > Duration.zero &&
      (position >= duration - const Duration(seconds: 15) ||
          position.inMilliseconds / duration.inMilliseconds >= .95)) {
    return Duration.zero;
  }
  return Duration(
    milliseconds: (position.inMilliseconds - rewindSeconds.clamp(0, 120) * 1000)
        .clamp(0, position.inMilliseconds),
  );
}

/// Shared by enqueue, retry and external handoff: manifest aliases must never
/// fall through to a direct-file job, including extensionless MPD endpoints.
bool isSegmentedMediaSource(MediaSource source) {
  final path = Uri.tryParse(source.url)?.path.toLowerCase() ?? '';
  final type = source.type.split(';').first.trim().toLowerCase();
  return path.endsWith('.m3u8') ||
      path.endsWith('.mpd') ||
      type == 'mpd' ||
      RegExp(r'hls|dash|m3u8|mpegurl').hasMatch(type);
}

String? downloadUnsupportedReason(MediaSource source) {
  if (!isRemoteMedia(source.url)) {
    return 'Only public HTTP(S) files can be downloaded.';
  }
  if (isSegmentedMediaSource(source)) {
    return 'Use offline HLS/DASH segment packaging instead of a direct video file.';
  }
  return null;
}

String downloadFilename({
  required String title,
  required String identity,
  required String url,
}) {
  var name = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'^\.+_?'), '')
      .trim();
  if (name.isEmpty) name = 'Video';
  if (name.length > 90) name = name.substring(0, 90);
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  final ext =
      RegExp(r'\.(mp4|mkv|webm|mov|avi|m4v|ts)$').firstMatch(path)?.group(1) ??
      'mp4';
  return '${name}_$identity.$ext';
}

bool isRemoteMedia(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}

MediaSource? selectSource(
  Iterable<MediaSource> sources, {
  String preferredQuality = '',
}) {
  final options = playableSources(sources);
  if (options.isEmpty) return null;
  return options.firstWhere(
    (s) => s.quality == preferredQuality,
    orElse: () => options.first,
  );
}

List<MediaSource> playableSources(Iterable<MediaSource> sources) {
  final seen = <String>{};
  return sources
      .where((s) => !s.isTrailer && isRemoteMedia(s.url) && seen.add(s.url))
      .toList();
}

/// Strict Unicode first; legacy Persian/Arabic files commonly use Windows-1256.
String decodeSubtitle(List<int> bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 255 && bytes[1] == 254) ||
          (bytes[0] == 254 && bytes[1] == 255))) {
    final little = bytes[0] == 255;
    if (bytes.length.isOdd) {
      throw const FormatException('Truncated UTF-16 subtitle');
    }
    return String.fromCharCodes([
      for (var i = 2; i + 1 < bytes.length; i += 2)
        little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
    ]);
  }
  try {
    return utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
  } on FormatException {
    return String.fromCharCodes(
      bytes.map((b) => b < 128 ? b : _windows1256[b - 128]),
    );
  }
}

// Unicode mapping of the Windows-1256 high-byte range (not Latin-1).
const _windows1256 = [
  8364,
  1662,
  8218,
  402,
  8222,
  8230,
  8224,
  8225,
  710,
  8240,
  1657,
  8249,
  338,
  1670,
  1688,
  1672,
  1711,
  8216,
  8217,
  8220,
  8221,
  8226,
  8211,
  8212,
  1705,
  8482,
  1681,
  8250,
  339,
  8204,
  8205,
  1722,
  160,
  1548,
  162,
  163,
  164,
  165,
  166,
  167,
  168,
  169,
  1726,
  171,
  172,
  173,
  174,
  175,
  176,
  177,
  178,
  179,
  180,
  181,
  182,
  183,
  184,
  185,
  1563,
  187,
  188,
  189,
  190,
  1567,
  1729,
  1569,
  1570,
  1571,
  1572,
  1573,
  1574,
  1575,
  1576,
  1577,
  1578,
  1579,
  1580,
  1581,
  1582,
  1583,
  1584,
  1585,
  1586,
  1587,
  1588,
  1589,
  1590,
  215,
  1591,
  1592,
  1593,
  1594,
  1600,
  1601,
  1602,
  1603,
  224,
  1604,
  226,
  1605,
  1606,
  1607,
  1608,
  231,
  232,
  233,
  234,
  235,
  1609,
  1610,
  238,
  239,
  1611,
  1612,
  1613,
  1614,
  244,
  1615,
  1616,
  247,
  1617,
  249,
  1618,
  251,
  252,
  8206,
  8207,
  1746,
];

class SubtitleVariant {
  const SubtitleVariant(this.language, this.label, this.url);
  final String language, label, url;
}

/// Accept flat lists as well as language groups containing release variants.
Map<String, List<SubtitleVariant>> subtitleGroups(
  List<Map<String, dynamic>> rows,
) {
  final result = <String, List<SubtitleVariant>>{};
  final seen = <String>{};
  String text(dynamic value) => value is Map
      ? '${value['name'] ?? value['title'] ?? value['code'] ?? ''}'
      : value is String
      ? value
      : '';
  void visit(Map item, String inherited) {
    final lang = text(item['language']).trim();
    final language = lang.isEmpty ? inherited : lang;
    final url = text(item['url'] ?? item['link']);
    if (isRemoteMedia(url) && seen.add(url)) {
      final label = text(item['title'] ?? item['name'] ?? item['quality']);
      (result[language] ??= []).add(
        SubtitleVariant(language, label.isEmpty ? 'Subtitle' : label, url),
      );
    }
    for (final key in ['subtitles', 'variants', 'files', 'releases', 'items']) {
      final children = item[key];
      if (children is List) {
        for (final child in children.whereType<Map>()) {
          visit(child, language);
        }
      }
    }
  }

  for (final item in rows) {
    visit(item, 'Other');
  }
  return result;
}

Future<void> applyPlayerOptions(
  AppSettings prefs, {
  required Future<void> Function(double) rate,
  required Future<void> Function(bool) audioOnly,
  required Future<void> Function(double) volume,
  bool Function()? current,
}) async {
  if (current != null && !current()) return;
  await rate(prefs.playbackSpeed);
  if (current != null && !current()) return;
  await audioOnly(prefs.audioOnly);
  if (current != null && !current()) return;
  if (prefs.rememberVolume) await volume(prefs.playerVolume);
}

AppSettings resetSubtitleSettings(AppSettings prefs) {
  final defaults = AppSettings();
  return prefs.copyWith(
    subtitleEnabled: defaults.subtitleEnabled,
    subtitleFontFamily: defaults.subtitleFontFamily,
    subtitleFontSize: defaults.subtitleFontSize,
    subtitleColor: defaults.subtitleColor,
    subtitleBackground: defaults.subtitleBackground,
    subtitleDelay: defaults.subtitleDelay,
  );
}

AppSettings resetPlayerSettings(AppSettings prefs) {
  final d = AppSettings();
  return resetSubtitleSettings(prefs).copyWith(
    playbackSpeed: d.playbackSpeed,
    audioDelay: d.audioDelay,
    videoFit: d.videoFit,
    audioOnly: d.audioOnly,
    playerVolume: d.playerVolume,
    rememberVolume: d.rememberVolume,
    backgroundAudio: d.backgroundAudio,
    closeOnCompletion: d.closeOnCompletion,
    resumeRewindSeconds: d.resumeRewindSeconds,
    skipSeconds: d.skipSeconds,
    resumePlayback: d.resumePlayback,
    autoplay: d.autoplay,
    autoNext: d.autoNext,
    orientation: d.orientation,
    externalPlayer: d.externalPlayer,
    externalPlayerPackage: d.externalPlayerPackage,
  );
}

String mediaContentType(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.endsWith('.m3u8')) return 'application/x-mpegURL';
  if (path.endsWith('.mpd')) return 'application/dash+xml';
  if (path.endsWith('.webm')) return 'video/webm';
  if (path.endsWith('.mkv')) return 'video/x-matroska';
  return 'video/mp4';
}
