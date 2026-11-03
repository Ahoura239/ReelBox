import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'media_helpers.dart';
import 'media_platform.dart';
import 'cast_media_share.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.source,
    this.episode,
    this.playlist = const [],
    this.alternatives = const [],
    this.localFile,
    this.playerFactory,
    this.videoControllerFactory,
    this.videoSurfaceBuilder,
    this.castShareFactory,
  });
  final TitleRecord title;
  final MediaSource source;
  final EpisodeRecord? episode;
  final List<EpisodeRecord> playlist;
  final List<MediaSource> alternatives;
  final String? localFile;

  /// Injectable engine boundaries for deterministic control/lifecycle tests.
  @visibleForTesting
  final Player Function()? playerFactory;
  @visibleForTesting
  final VideoController? Function(Player)? videoControllerFactory;
  @visibleForTesting
  final Widget Function(BoxFit)? videoSurfaceBuilder;
  @visibleForTesting
  final Future<CastMediaLease> Function({
    required Map<String, dynamic> payload,
    String? localFile,
    String? subtitleText,
  })?
  castShareFactory;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  Player? _player;
  VideoController? _video;
  AppState? _app;
  late MediaSource _source = widget.source;
  late EpisodeRecord? _episode = widget.episode;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _saveTimer, _hideTimer;
  final _checkpoint = PlaybackCheckpoint();
  final _systemControls = PlayerSystemControls();
  Duration get _position =>
      _native?.casting == true ? _native!.position : _checkpoint.position;
  set _position(Duration value) => _checkpoint.position = value;
  Duration get _duration =>
      _native?.casting == true ? _native!.duration : _checkpoint.duration;
  set _duration(Duration value) => _checkpoint.duration = value;
  bool _started = false, _busy = true, _playing = false, _locked = false;
  bool _controls = true, _subtitles = true, _audioOnly = false, _pip = false;
  String _videoFit = 'contain';
  bool get _fill => _videoFit == 'cover';
  BoxFit get _videoBoxFit => switch (_videoFit) {
    'fill' => BoxFit.fill,
    'cover' => BoxFit.cover,
    _ => BoxFit.contain,
  };
  String? _error;
  PlayerNativeSession? _native;
  String? _subtitleUrl;
  String? _subtitleText;
  SubtitleTrack _selectedSubtitleTrack = SubtitleTrack.auto();
  final _loadedSubtitleTracks = <SubtitleTrack, String?>{};
  int _subtitleSelectionRevision = 0;
  CastMediaLease? _castLease;
  int _shareGeneration = 0;
  bool _muted = false, _fullscreen = true, _settingsOpen = false;
  double _castVolume = .5;
  bool get _casting => _native?.casting == true;
  bool get _effectivePlaying => _casting ? _native!.playing : _playing;
  String get _mediaTitle => _episode == null
      ? widget.title.title
      : '${widget.title.title} — ${_episode!.title}';
  Map<String, dynamic> _mediaPayload() => {
    'url': widget.localFile ?? _source.url,
    'title': _mediaTitle,
    'contentType': mediaContentType(_source.url),
    'positionMs': _position.inMilliseconds,
  };
  Future<Map<String, dynamic>> _prepareCastMedia() async {
    final generation = ++_shareGeneration;
    final payload = _mediaPayload();
    final text = _subtitles ? _subtitleText : null;
    final previous = _castLease;
    _castLease = null;
    await previous?.close();
    final prepare = widget.castShareFactory ?? CastMediaShare.prepare;
    final lease = await prepare(
      payload: payload,
      localFile: widget.localFile,
      subtitleText: text,
    );
    if (!mounted || !_lifecycle.ownsSystem || generation != _shareGeneration) {
      await lease.close();
      throw StateError('The Cast request is no longer current.');
    }
    _castLease = lease;
    return lease.payload;
  }

  Future<void> _revokeCastMedia() async {
    _shareGeneration++;
    final lease = _castLease;
    _castLease = null;
    await lease?.close();
  }

  Future<void> _invalidateCastMedia() =>
      _native?.invalidateCastMedia() ?? _revokeCastMedia();

  late final _lifecycle = PlaybackLifecycle(isMounted: () => mounted);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.read(context);
    if (!_started) {
      _started = true;
      _subtitles = _app!.prefs.subtitleEnabled;
      _videoFit = _app!.prefs.videoFit;
      _audioOnly = _app!.prefs.audioOnly;
      unawaited(_initialize());
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _guard(Future<void> operation) {
    unawaited(
      operation.catchError((Object error) {
        if (mounted) {
          setState(() {
            _error =
                'The media server or player could not complete this operation.';
            _busy = false;
            _controls = true;
          });
        }
      }),
    );
  }

  Future<void> _initialize() async {
    if (widget.localFile == null && !isRemoteMedia(_source.url)) {
      if (mounted) {
        setState(() {
          _error = 'Only HTTP(S) media sources can be played.';
          _busy = false;
        });
      }
      return;
    }
    try {
      WidgetsBinding.instance.addObserver(this);
      final player = _player = widget.playerFactory?.call() ?? Player();
      _video = widget.videoControllerFactory != null
          ? widget.videoControllerFactory!(player)
          : VideoController(player);
      _subscriptions.add(
        player.stream.position.listen((value) {
          if (_casting) return;
          _position = value;
          _refresh();
        }),
      );
      _subscriptions.add(
        player.stream.duration.listen((value) {
          if (_casting) return;
          _duration = value;
          _refresh();
        }),
      );
      _subscriptions.add(
        player.stream.playing.listen((value) {
          _playing = value;
          if (_casting) return;
          if (!value) _controls = true;
          _refresh();
          if (value) _scheduleHide();
          _guard(_syncBackground());
        }),
      );
      _subscriptions.add(
        player.stream.buffering.listen((value) {
          if (_casting) return;
          _busy = value;
          _refresh();
        }),
      );
      _subscriptions.add(player.stream.tracks.listen((_) => _refresh()));
      _subscriptions.add(
        player.stream.error.listen((message) {
          if (mounted) {
            setState(() {
              _error = 'The media server is unavailable or this source cannot be decoded.';
              _busy = false;
              _controls = true;
            });
          }
        }),
      );
      _subscriptions.add(
        player.stream.completed.listen((completed) {
          if (completed && !_casting) _guard(_completed());
        }),
      );
      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_effectivePlaying) _guard(_save());
        _guard(_syncBackground());
      });
      final ready = await _lifecycle.setup([
        if (MediaPlatform.supported)
          () async {
            _native = PlayerNativeSession(
              invoke: (method, args) =>
                  MediaPlatform.invoke<dynamic>(method, args),
              local: _localCommand,
              media: _mediaPayload,
              prepareMedia: _prepareCastMedia,
              revokeMedia: _revokeCastMedia,
              isPlaying: () => _effectivePlaying,
              isCurrent: () => _lifecycle.ownsSystem,
              changed: () {
                _pip = _native!.inPip;
                if (!_effectivePlaying) _controls = true;
                _refresh();
              },
              failure: _notice,
            )..claim();
            await _systemControls.capture();
          },
        if (MediaPlatform.supported)
          () async {
            _brightness = _systemControls.brightness;
            _volume = _systemControls.volume;
            await MediaPlatform.setActive(true);
          },
        () => SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
        _orientation,
      ]);
      if (!ready) return;
      await _open(_source, episode: _episode);
      if (_lifecycle.ownsSystem && MediaPlatform.supported) {
        try {
          await _native?.refreshCast();
        } catch (_) {
          /* Cast unavailable on this device. */
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The player could not initialize on this device.';
          _busy = false;
        });
      }
    }
  }

  Future<void> _orientation() async {
    final mode = _app!.prefs.orientation;
    await SystemChrome.setPreferredOrientations(
      mode == 'landscape'
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : mode == 'portrait'
          ? [DeviceOrientation.portraitUp]
          : DeviceOrientation.values,
    );
  }

  Future<void> _open(
    MediaSource source, {
    EpisodeRecord? episode,
    Duration? position,
  }) async {
    if (_player == null) return;
    if (widget.localFile == null && !isRemoteMedia(source.url)) {
      throw StateError('Invalid source');
    }
    _subtitleSelectionRevision++;
    final revocation = _invalidateCastMedia();
    await _lifecycle.open(
      save: () async {
        await revocation;
        await _save();
      },
      dispatch: (current) async {
        final episodeChanged = _episode?.id != episode?.id;
        _source = source;
        _episode = episode;
        _subtitleUrl = null;
        _subtitleText = null;
        _selectedSubtitleTrack = SubtitleTrack.auto();
        if (episodeChanged) _loadedSubtitleTracks.clear();
        _error = null;
        _busy = true;
        _checkpoint.beginOpen();
        _refresh();
        final saved = _app!.history
            .where(
              (e) =>
                  e.title.libraryKey == widget.title.libraryKey &&
                  e.episodeId == episode?.id,
            )
            .firstOrNull;
        final start =
            position ??
            (_app!.prefs.resumePlayback && saved != null
                ? resumePosition(
                    position: Duration(
                      milliseconds: (saved.positionSeconds * 1000).round(),
                    ),
                    duration: Duration(
                      milliseconds: (saved.durationSeconds * 1000).round(),
                    ),
                    rewindSeconds: _app!.prefs.resumeRewindSeconds,
                  )
                : Duration.zero);
        if (!current()) return;
        await dispatchMediaOpen(
          open: _player!.open,
          uri: widget.localFile ?? source.url,
          start: start,
          autoplay: !_casting && _app!.prefs.autoplay,
        );
        if (!mounted || !current()) return;
        _checkpoint.didOpen();
        await _applyOptions(current: current);
        if (!current()) return;
        if (_casting) {
          _native!.position = start;
          await _native!.loadCast();
        }
        if (!current()) return;
        await _applyDelays(current: current);
        if (!current()) return;
        _busy = false;
        _refresh();
        _scheduleHide();
      },
    );
  }

  Future<void> _applyDelays({bool Function()? current}) async {
    if (current != null && !current()) return;
    final platform = _player?.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('sub-delay', '${_app!.prefs.subtitleDelay}');
      if (current != null && !current()) return;
      await platform.setProperty('audio-delay', '${_app!.prefs.audioDelay}');
    }
  }

  Future<void> _save() async {
    if (_player == null ||
        _source.isTrailer ||
        _app == null ||
        !(_checkpoint.canPersist || (_casting && _position > Duration.zero))) {
      return;
    }
    await _app!.recordWatch(
      widget.title,
      episodeId: _episode?.id,
      episodeTitle: _episode?.title ?? '',
      sourceUrl: _source.url,
      positionSeconds: _position.inMilliseconds / 1000,
      durationSeconds: _duration.inMilliseconds / 1000,
    );
  }

  Future<void> _next() async {
    final episode = nextEpisode(widget.playlist, _episode?.id);
    if (episode == null) return;
    final source = selectSource(
      episode.sources,
      preferredQuality: _source.quality,
    );
    if (source == null) throw StateError('No source for the next episode');
    await _open(source, episode: episode, position: Duration.zero);
  }

  Future<void> _previous() async {
    final i = widget.playlist.indexWhere((e) => e.id == _episode?.id);
    if (i <= 0) return;
    final episode = widget.playlist[i - 1];
    final source = selectSource(
      episode.sources,
      preferredQuality: _source.quality,
    );
    if (source != null) await _open(source, episode: episode);
  }

  void _seek(int direction) {
    if (_locked || widget.title.isChannel || _player == null) return;
    final value =
        _position + Duration(seconds: direction * _app!.prefs.skipSeconds);
    _guard(
      _command(
        'seek',
        position: Duration(
          milliseconds: value.inMilliseconds.clamp(
            0,
            _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1 << 40,
          ),
        ),
      ),
    );
    _showControls();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _effectivePlaying && !_locked && !_settingsOpen) {
        setState(() => _controls = false);
      }
    });
  }

  void _showControls() {
    if (mounted) setState(() => _controls = true);
    _scheduleHide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _guard(_background());
    if (state == AppLifecycleState.resumed &&
        MediaPlatform.supported &&
        _lifecycle.ownsSystem) {
      _guard(_native!.refreshCast());
    }
  }

  Future<void> _background() async {
    await _save();
    final inPip =
        MediaPlatform.supported &&
        (await MediaPlatform.invoke<bool>('isInPip') ?? false);
    if (!_lifecycle.ownsSystem) return;
    if (_casting || _app!.prefs.backgroundAudio) {
      await _syncBackground();
    } else if (!inPip) {
      await _player?.pause();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _native?.release();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    unawaited(
      _lifecycle
          .dispose(() async {
            if (_player == null) return;
            await _native?.stopBackground();
            await Future.wait<void>([
              _systemControls.restore(),
              MediaPlatform.setActive(false),
              SystemChrome.setPreferredOrientations(DeviceOrientation.values),
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
            ]);
          })
          .catchError((_) {}),
    );
    if (_player != null) {
      unawaited(_save().catchError((_) {}));
      unawaited(_player!.dispose());
    }
    super.dispose();
  }

  String _clock(Duration duration) => duration.toString().split('.').first;
  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    final alternatives = (_episode?.sources ?? widget.alternatives)
        .where((s) => !s.isTrailer)
        .toList();
    return Focus(
      // The inner PlayerInteraction focus must own keyboard events; an
      // autofocus ancestor prevents its CallbackShortcuts from seeing them.
      autofocus: false,
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) _guard(_save());
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Theme(
            data: ThemeData.dark(useMaterial3: true),
            child: PlayerInteraction(
              locked: _locked,
              controlsVisible: _controls || !_effectivePlaying,
              onAction: _action,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.videoSurfaceBuilder != null &&
                      !_audioOnly &&
                      !_casting)
                    widget.videoSurfaceBuilder!(_videoBoxFit)
                  else if (_video != null && !_audioOnly && !_casting)
                    Video(
                      controller: _video!,
                      controls: NoVideoControls,
                      fit: _videoBoxFit,
                      pauseUponEnteringBackgroundMode: false,
                      subtitleViewConfiguration: SubtitleViewConfiguration(
                        visible: _subtitles,
                        style: TextStyle(
                          fontFamily: prefs.subtitleFontFamily,
                          fontSize: prefs.subtitleFontSize,
                          color: Color(prefs.subtitleColor),
                          backgroundColor: Color(prefs.subtitleBackground),
                          height: 1.4,
                        ),
                        padding: EdgeInsets.fromLTRB(
                          18,
                          0,
                          18,
                          _controls ? 150 : 28,
                        ),
                      ),
                    ),
                  if (_audioOnly || _casting)
                    Center(
                      child: Icon(
                        _casting
                            ? Icons.cast_connected
                            : Icons.headphones_rounded,
                        color: Colors.white54,
                        size: 100,
                      ),
                    ),
                  // Surface gestures sit below controls, not above them in the
                  // double-tap arena, so transport buttons respond immediately.
                  PlayerSurfaceGestures(locked: _locked, onAction: _action),
                  if (!_effectivePlaying &&
                      !_busy &&
                      _error == null &&
                      !_pip &&
                      !_locked)
                    Center(
                      child: IconButton.filledTonal(
                        tooltip: 'Play',
                        iconSize: 48,
                        onPressed: () => _guard(_command('play')),
                        icon: const Icon(Icons.play_arrow),
                      ),
                    ),
                  if (_casting)
                    Positioned(
                      top: 80,
                      left: 24,
                      right: 24,
                      child: Text(
                        'Casting to ${_native!.deviceName}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  if (_busy && _error == null)
                    const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.white70,
                              size: 44,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              tr(
                                context,
                                'Unable to play this source',
                                'پخش این منبع ممکن نیست',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: () => _player == null
                                  ? _guard(_initialize())
                                  : _guard(_open(_source, episode: _episode)),
                              child: Text(tr(context, 'Retry', 'تلاش دوباره')),
                            ),
                            if (MediaPlatform.supported &&
                                isRemoteMedia(_source.url))
                              TextButton(
                                onPressed: () => _guard(_externalPlayer()),
                                child: Text(
                                  tr(
                                    context,
                                    'Try an external player',
                                    'پخش‌کننده خارجی',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if ((_controls || _error != null) && !_locked && !_pip)
                    SafeArea(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                          child: Row(
                            children: [
                              BackButton(color: Colors.white),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.title.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (_episode != null)
                                      Text(
                                        _episode!.title,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: tr(
                                  context,
                                  'Lock controls',
                                  'قفل کنترل‌ها',
                                ),
                                onPressed: () => setState(() => _locked = true),
                                icon: const Icon(Icons.lock_outline),
                              ),
                              if (MediaPlatform.supported)
                                IconButton(
                                  tooltip: _casting
                                      ? 'Cast controls'
                                      : 'Cast to device',
                                  onPressed: () => _guard(_castControls()),
                                  icon: Icon(
                                    _casting
                                        ? Icons.cast_connected
                                        : Icons.cast,
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Fullscreen',
                                onPressed: () => _action('fullscreen'),
                                icon: Icon(
                                  _fullscreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                ),
                              ),
                              if (MediaPlatform.supported && !_casting)
                                IconButton(
                                  tooltip: 'Picture in picture',
                                  onPressed: () async {
                                    try {
                                      final ok = await MediaPlatform.enterPip();
                                      if (!ok && mounted) {
                                        _notice(
                                          'Picture in picture is unavailable on this device.',
                                        );
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        _notice(
                                          'Picture in picture is unavailable.',
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.picture_in_picture_alt,
                                  ),
                                ),
                              IconButton(
                                tooltip: tr(
                                  context,
                                  'Player settings',
                                  'تنظیمات پخش',
                                ),
                                onPressed: _player == null ? null : _settings,
                                icon: const Icon(Icons.tune),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_controls &&
                      !_locked &&
                      !_pip &&
                      _error == null &&
                      _player != null)
                    SafeArea(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    widget.title.isChannel
                                        ? 'LIVE'
                                        : _clock(_position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _duration.inMilliseconds > 0
                                          ? (_position.inMilliseconds /
                                                    _duration.inMilliseconds)
                                                .clamp(0, 1)
                                          : 0,
                                      onChanged:
                                          widget.title.isChannel ||
                                              _duration == Duration.zero
                                          ? null
                                          : (v) => _guard(
                                              _command(
                                                'seek',
                                                position: Duration(
                                                  milliseconds:
                                                      (_duration.inMilliseconds *
                                                              v)
                                                          .round(),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  Text(
                                    _clock(_duration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    tooltip: tr(
                                      context,
                                      'Previous episode',
                                      'قسمت قبلی',
                                    ),
                                    onPressed:
                                        widget.playlist.indexWhere(
                                              (e) => e.id == _episode?.id,
                                            ) >
                                            0
                                        ? () => _guard(_previous())
                                        : null,
                                    icon: const Icon(Icons.skip_previous),
                                  ),
                                  IconButton(
                                    tooltip: tr(context, 'Back', 'عقب'),
                                    onPressed: () => _seek(-1),
                                    icon: const Icon(Icons.replay_10),
                                  ),
                                  IconButton.filled(
                                    tooltip: _effectivePlaying
                                        ? 'Pause'
                                        : 'Play',
                                    iconSize: 30,
                                    onPressed: () {
                                      _guard(
                                        _command(
                                          _effectivePlaying ? 'pause' : 'play',
                                        ),
                                      );
                                      _showControls();
                                    },
                                    icon: Icon(
                                      _effectivePlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: tr(context, 'Forward', 'جلو'),
                                    onPressed: () => _seek(1),
                                    icon: const Icon(Icons.forward_10),
                                  ),
                                  IconButton(
                                    tooltip: tr(
                                      context,
                                      'Next episode',
                                      'قسمت بعدی',
                                    ),
                                    onPressed:
                                        nextEpisode(
                                              widget.playlist,
                                              _episode?.id,
                                            ) ==
                                            null
                                        ? null
                                        : () => _guard(_next()),
                                    icon: const Icon(Icons.skip_next),
                                  ),
                                  IconButton(
                                    tooltip: tr(
                                      context,
                                      'Fit or fill',
                                      'اندازه تصویر',
                                    ),
                                    onPressed: () => _action('fit'),
                                    icon: Icon(
                                      _fill
                                          ? Icons.fit_screen
                                          : Icons.aspect_ratio,
                                    ),
                                  ),
                                ],
                              ),
                              if (alternatives.length > 1)
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final source in alternatives)
                                      ChoiceChip(
                                        label: Text(
                                          source.quality.isEmpty
                                              ? source.type
                                              : source.quality,
                                        ),
                                        selected: source.url == _source.url,
                                        onSelected: (v) {
                                          if (v) {
                                            _guard(
                                              _open(
                                                source,
                                                episode: _episode,
                                                position: _position,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_locked && !_pip)
                    SafeArea(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: IconButton.filledTonal(
                          tooltip: tr(
                            context,
                            'Unlock controls',
                            'باز کردن قفل',
                          ),
                          onPressed: () => setState(() {
                            _locked = false;
                            _controls = true;
                          }),
                          icon: const Icon(Icons.lock_open),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyOptions({bool Function()? current}) async {
    final prefs = _app!.prefs;
    _subtitles = prefs.subtitleEnabled;
    _videoFit = prefs.videoFit;
    _audioOnly = prefs.audioOnly;
    await applyPlayerOptions(
      prefs,
      rate: (v) => _player!.setRate(v),
      audioOnly: (v) =>
          _player!.setVideoTrack(v ? VideoTrack.no() : VideoTrack.auto()),
      volume: (v) async {
        if (MediaPlatform.supported && _lifecycle.ownsSystem) {
          await MediaPlatform.invoke<void>('setVolume', {'value': v});
          _volume = v;
        }
      },
      current: current,
    );
    _refresh();
  }

  Future<void> _localCommand(String action, Duration? position) async {
    if (!mounted || !_lifecycle.ownsSystem || _player == null) return;
    switch (action) {
      case 'play':
        await _player!.play();
      case 'pause':
        await _player!.pause();
      case 'seek':
        if (position != null) await _player!.seek(position);
      case 'stop':
        await _player!.pause();
        await _player!.seek(Duration.zero);
      case 'next':
        await _next();
      case 'previous':
        await _previous();
    }
  }

  Future<void> _command(String action, {Duration? position}) async {
    if (_native != null) {
      await _native!.command(action, position: position);
    } else {
      await _localCommand(action, position);
    }
    if (mounted) _showControls();
  }

  Future<void> _syncBackground() async {
    if (!MediaPlatform.supported ||
        !_lifecycle.ownsSystem ||
        _app == null ||
        _native == null) {
      return;
    }
    await _native!.background(
      enabled: _app!.prefs.backgroundAudio,
      playing: _effectivePlaying,
      position: _position,
      duration: _duration,
    );
  }

  Future<void> _setSubtitles(bool enabled) async {
    if (enabled && _selectedSubtitleTrack.id == 'no') {
      return _selectSubtitleTrack(SubtitleTrack.auto());
    }
    final revocation = _invalidateCastMedia();
    final generation = _shareGeneration;
    _subtitles = enabled;
    _refresh();
    await revocation;
    await _app!.updateSettings(_app!.prefs.copyWith(subtitleEnabled: enabled));
    if (mounted &&
        _lifecycle.ownsSystem &&
        generation == _shareGeneration &&
        _casting) {
      await _native!.loadCast();
    }
  }

  Future<void> _setAudioOnly(bool enabled) async {
    _audioOnly = enabled;
    _refresh();
    await _app!.updateSettings(_app!.prefs.copyWith(audioOnly: enabled));
    if (!mounted || !_lifecycle.ownsSystem) return;
    await _player!.setVideoTrack(enabled ? VideoTrack.no() : VideoTrack.auto());
    await _syncBackground();
  }

  Future<void> _setFit(bool fill) async {
    final mode = fill ? 'cover' : 'contain';
    if (_videoFit == mode) return;
    _videoFit = mode;
    _refresh();
    await _app!.updateSettings(
      _app!.prefs.copyWith(videoFit: fill ? 'cover' : 'contain'),
    );
  }

  Future<void> _setVolume(double value) async {
    value = value.clamp(0, 1);
    if (_casting) {
      _castVolume = value;
      await _native!.command('volume', value: value);
    } else if (MediaPlatform.supported && _lifecycle.ownsSystem) {
      _volume = value;
      await MediaPlatform.invoke<void>('setVolume', {'value': value});
      if (mounted) {
        await _app!.updateSettings(_app!.prefs.copyWith(playerVolume: value));
      }
    } else if (_player != null) {
      _volume = value;
      await _player!.setVolume(value * 100);
    }
    _refresh();
  }

  Future<void> _toggleMute() async {
    _muted = !_muted;
    if (_casting) {
      await _native!.command('volume', value: _muted ? 0 : _castVolume);
    } else {
      await _player?.setVolume(_muted ? 0 : 100);
    }
    _refresh();
  }

  Future<void> _setFullscreen(bool value) async {
    if (!_lifecycle.ownsSystem) return;
    _fullscreen = value;
    await SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _refresh();
  }

  void _action(String action) {
    if (_locked) return;
    switch (action) {
      case 'toggle':
        _guard(_command(_effectivePlaying ? 'pause' : 'play'));
      case 'play':
      case 'pause':
      case 'stop':
      case 'next':
      case 'previous':
        _guard(_command(action));
      case 'back':
        _seek(-1);
      case 'forward':
        _seek(1);
      case 'mute':
        _guard(_toggleMute());
      case 'subtitles':
        _guard(_setSubtitles(!_subtitles));
      case 'fullscreen':
        _guard(_setFullscreen(!_fullscreen));
      case 'exitFullscreen':
        _guard(_setFullscreen(false));
      case 'fit':
        _guard(_setFit(!_fill));
      case 'fill':
        _guard(_setFit(true));
      case 'contain':
        _guard(_setFit(false));
      case 'volumeUp':
        _guard(_setVolume((_casting ? _castVolume : _volume) + .05));
      case 'volumeDown':
        _guard(_setVolume((_casting ? _castVolume : _volume) - .05));
      case 'show':
        _showControls();
      case 'controls':
        if (mounted) setState(() => _controls = !_controls);
        if (_controls) _scheduleHide();
    }
  }

  Future<void> _completed() async {
    await _save();
    if (!mounted || !_lifecycle.ownsSystem) return;
    if (_app!.prefs.autoNext &&
        nextEpisode(widget.playlist, _episode?.id) != null) {
      await _next();
    } else if (_app!.prefs.closeOnCompletion) {
      Navigator.maybePop(context);
    } else {
      _controls = true;
      _refresh();
    }
  }

  Future<void> _reset({required bool subtitlesOnly}) async {
    await _app!.updateSettings(
      subtitlesOnly
          ? resetSubtitleSettings(_app!.prefs)
          : resetPlayerSettings(_app!.prefs),
    );
    if (!mounted || !_lifecycle.ownsSystem) return;
    if (!subtitlesOnly) {
      _muted = false;
      await _player!.setVolume(100);
      await _orientation();
      await _applyOptions();
      await _syncBackground();
    } else {
      _subtitles = _app!.prefs.subtitleEnabled;
    }
    await _applyDelays();
    _refresh();
  }

  Future<void> _castControls() async {
    if (!_native!.connected) {
      if (!await _native!.picker() && mounted) {
        _notice('Cast picker is unavailable on this device.');
      }
      return;
    }
    _settingsOpen = true;
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cast_connected),
                title: Text(_native!.deviceName),
                subtitle: Text(_mediaTitle),
              ),
              Text(
                'Use the player timeline and episode buttons to control the TV.',
              ),
              if (!_casting)
                FilledButton(
                  onPressed: () async {
                    await _native!.loadCast();
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                  child: const Text('Cast this video'),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Remote play/pause',
                    onPressed: !_casting
                        ? null
                        : () async {
                            await _command(
                              _effectivePlaying ? 'pause' : 'play',
                            );
                            if (sheet.mounted) update(() {});
                          },
                    icon: Icon(
                      _effectivePlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Choose Cast device',
                    onPressed: () => _guard(_native!.picker().then((_) {})),
                    icon: const Icon(Icons.cast),
                  ),
                ],
              ),
              Slider(
                value: _castVolume,
                onChanged: (v) {
                  update(() => _castVolume = v);
                  _guard(_setVolume(v));
                },
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  _guard(_native!.disconnect());
                },
                child: const Text('Disconnect and resume here'),
              ),
            ],
          ),
        ),
      ),
    );
    _settingsOpen = false;
    _scheduleHide();
  }

  Future<void> _externalPlayer() async {
    String? package = _app!.prefs.externalPlayerPackage;
    if (package == 'ask') {
      package = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in const {
                'ask': 'Android chooser',
                'org.videolan.vlc': 'VLC',
                'com.mxtech.videoplayer.ad': 'MX Player',
                'com.mxtech.videoplayer.pro': 'MX Player Pro',
                'is.xyz.mpv': 'mpv',
              }.entries)
                ListTile(
                  title: Text(entry.value),
                  onTap: () => Navigator.pop(sheet, entry.key),
                ),
            ],
          ),
        ),
      );
    }
    if (package == null || !mounted || !_lifecycle.ownsSystem) return;
    await _save();
    await MediaPlatform.openExternal(
      widget.localFile ?? _source.url,
      packageName: package,
      title: _mediaTitle,
      subtitleUrl: _subtitles ? _subtitleUrl : null,
      position: _position,
    );
    if (mounted && _lifecycle.ownsSystem) await _command('pause');
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _externalSubtitle() async {
    final selection = _subtitleSelectionRevision;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
    );
    if (file == null || !mounted || !_lifecycle.ownsSystem) return;
    final size = await file.length();
    if (size == null || size > 8 * 1024 * 1024) {
      throw StateError('Subtitle file is too large.');
    }
    final bytes = await file.readAsBytes();
    if (!mounted ||
        !_lifecycle.ownsSystem ||
        selection != _subtitleSelectionRevision) {
      return;
    }
    final data = decodeSubtitle(bytes);
    await _selectSubtitleTrack(SubtitleTrack.data(data, title: file.name));
  }

  Future<void> _selectSubtitleTrack(
    SubtitleTrack track, {
    String? sourceUrl,
  }) async {
    final revision = ++_subtitleSelectionRevision;
    final revocation = _invalidateCastMedia();
    await revocation;
    if (!mounted ||
        !_lifecycle.ownsSystem ||
        revision != _subtitleSelectionRevision) {
      return;
    }
    await _player!.setSubtitleTrack(track);
    if (!mounted ||
        !_lifecycle.ownsSystem ||
        revision != _subtitleSelectionRevision) {
      return;
    }
    _selectedSubtitleTrack = track;
    _subtitleText = track.data ? track.id : null;
    _subtitleUrl = track.data
        ? sourceUrl ?? _loadedSubtitleTracks[track]
        : null;
    if (track.data) {
      _loadedSubtitleTracks[track] = _subtitleUrl;
      if (_loadedSubtitleTracks.length > 4) {
        _loadedSubtitleTracks.remove(_loadedSubtitleTracks.keys.first);
      }
    }
    if (_casting && !track.data && track.id != 'no') {
      _notice(
        'Embedded subtitles cannot be shared; Cast continues without them',
      );
    }
    await _setSubtitles(track.id != 'no');
  }

  Future<void> _settings() async {
    _hideTimer?.cancel();
    _settingsOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final prefs = _app!.prefs;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: ListView(
                children: [
                  ListTile(
                    title: Text(
                      tr(context, 'Player settings', 'تنظیمات پخش'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Mute'),
                    value: _muted,
                    onChanged: (_) async {
                      await _toggleMute();
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Fill video frame'),
                    value: _fill,
                    onChanged: (v) async {
                      await _setFit(v);
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Remember system volume'),
                    subtitle: const Text(
                      'Only when enabled, restore saved volume when opening media.',
                    ),
                    value: prefs.rememberVolume,
                    onChanged: (v) async {
                      await _app!.updateSettings(
                        _app!.prefs.copyWith(
                          rememberVolume: v,
                          playerVolume: _volume,
                        ),
                      );
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Background audio'),
                    subtitle: const Text(
                      'Keep audio playing with notification and lock-screen controls.',
                    ),
                    value: prefs.backgroundAudio,
                    onChanged: (v) async {
                      await _app!.updateSettings(
                        _app!.prefs.copyWith(backgroundAudio: v),
                      );
                      await _syncBackground();
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Autoplay when opening media'),
                    value: prefs.autoplay,
                    onChanged: (v) async {
                      await _app!.updateSettings(
                        _app!.prefs.copyWith(autoplay: v),
                      );
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Automatically play next episode'),
                    value: prefs.autoNext,
                    onChanged: (v) async {
                      await _app!.updateSettings(
                        _app!.prefs.copyWith(autoNext: v),
                      );
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Close player on completion'),
                    value: prefs.closeOnCompletion,
                    onChanged: (v) async {
                      await _app!.updateSettings(
                        _app!.prefs.copyWith(closeOnCompletion: v),
                      );
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Resume previous position'),
                    value: prefs.resumePlayback,
                    onChanged: (v) async {
                      await _app!.updateSettings(
                        _app!.prefs.copyWith(resumePlayback: v),
                      );
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  ListTile(
                    title: const Text('Resume rewind'),
                    trailing: DropdownButton<int>(
                      value: prefs.resumeRewindSeconds,
                      items: [
                        for (final v in {
                          ...[0, 5, 10, 15, 30, 60, 120],
                          prefs.resumeRewindSeconds,
                        })
                          DropdownMenuItem(value: v, child: Text('$v s')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await _app!.updateSettings(
                          _app!.prefs.copyWith(resumeRewindSeconds: v),
                        );
                        if (sheetContext.mounted) update(() {});
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Subtitle font'),
                    trailing: DropdownButton<String>(
                      value: prefs.subtitleFontFamily,
                      items: [
                        for (final v in {
                          'sans-serif',
                          'serif',
                          'monospace',
                          prefs.subtitleFontFamily,
                        })
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await _app!.updateSettings(
                          _app!.prefs.copyWith(subtitleFontFamily: v),
                        );
                        _refresh();
                        if (sheetContext.mounted) update(() {});
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Subtitle color'),
                    trailing: Wrap(
                      children: [
                        for (final c in [0xFFFFFFFF, 0xFFFFFF00, 0xFF00FFFF])
                          IconButton(
                            tooltip: c == 0xFFFFFFFF
                                ? 'White subtitles'
                                : c == 0xFFFFFF00
                                ? 'Yellow subtitles'
                                : 'Cyan subtitles',
                            icon: Icon(Icons.circle, color: Color(c)),
                            onPressed: () async {
                              await _app!.updateSettings(
                                _app!.prefs.copyWith(subtitleColor: c),
                              );
                              if (sheetContext.mounted) update(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Subtitle background'),
                    value: prefs.subtitleBackground != 0,
                    onChanged: (v) async {
                      await _app!.updateSettings(
                        _app!.prefs.copyWith(
                          subtitleBackground: v ? 0x80000000 : 0,
                        ),
                      );
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  ListTile(
                    title: const Text('Reset subtitle styling and timing'),
                    onTap: () async {
                      await _reset(subtitlesOnly: true);
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  ListTile(
                    title: const Text('Reset all player options'),
                    subtitle: const Text(
                      'Does not clear your library or playback history.',
                    ),
                    onTap: () async {
                      await _reset(subtitlesOnly: false);
                      if (sheetContext.mounted) update(() {});
                    },
                  ),
                  ListTile(
                    title: const Text('External player preference'),
                    trailing: DropdownButton<String>(
                      value: prefs.externalPlayerPackage,
                      items: [
                        for (final e in const {
                          'ask': 'Ask',
                          'org.videolan.vlc': 'VLC',
                          'com.mxtech.videoplayer.ad': 'MX Player',
                          'com.mxtech.videoplayer.pro': 'MX Pro',
                          'is.xyz.mpv': 'mpv',
                        }.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await _app!.updateSettings(
                          _app!.prefs.copyWith(externalPlayerPackage: v),
                        );
                        if (sheetContext.mounted) update(() {});
                      },
                    ),
                  ),
                  if (MediaPlatform.supported && widget.localFile == null)
                    ListTile(
                      leading: const Icon(Icons.video_library_outlined),
                      title: const Text('Open video in embedded browser'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _guard(
                          MediaPlatform.invoke<bool>('openEmbedded', {
                            'url': _source.url,
                            'title': _mediaTitle,
                          }).then((ok) {
                            if (ok != true) {
                              _notice('Embedded playback is unavailable.');
                            }
                          }),
                        );
                      },
                    ),
                  ListTile(
                    title: Text(tr(context, 'Speed', 'سرعت')),
                    trailing: DropdownButton<double>(
                      value:
                          [
                            0.5,
                            .75,
                            1.0,
                            1.25,
                            1.5,
                            1.75,
                            2.0,
                          ].contains(prefs.playbackSpeed)
                          ? prefs.playbackSpeed
                          : 1.0,
                      items: [
                        for (final rate in [
                          0.5,
                          .75,
                          1.0,
                          1.25,
                          1.5,
                          1.75,
                          2.0,
                        ])
                          DropdownMenuItem(value: rate, child: Text('$rate×')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await _player!.setRate(v);
                        await _app!.updateSettings(
                          prefs.copyWith(playbackSpeed: v),
                        );
                        if (sheetContext.mounted) update(() {});
                      },
                    ),
                  ),
                  SwitchListTile(
                    title: Text(tr(context, 'Show subtitles', 'نمایش زیرنویس')),
                    value: _subtitles,
                    onChanged: (v) {
                      _guard(_setSubtitles(v));
                      update(() {});
                    },
                  ),
                  for (final track in {
                    ..._loadedSubtitleTracks.keys,
                    ..._player!.state.tracks.subtitle,
                  })
                    ListTile(
                      key: ValueKey(track),
                      leading: const Icon(Icons.subtitles_outlined),
                      title: Text(track.title ?? track.language ?? track.id),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _guard(_selectSubtitleTrack(track));
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.file_open_outlined),
                    title: Text(
                      tr(context, 'Load subtitle file', 'انتخاب فایل زیرنویس'),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _guard(_externalSubtitle());
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(
                      tr(
                        context,
                        'Subtitles from service',
                        'زیرنویس‌های سرویس',
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _guard(_remoteSubtitles());
                    },
                  ),
                  for (final track in _player!.state.tracks.audio)
                    ListTile(
                      leading: const Icon(Icons.audiotrack),
                      title: Text(track.title ?? track.language ?? track.id),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _guard(_player!.setAudioTrack(track));
                      },
                    ),
                  ListTile(
                    title: Text(tr(context, 'Subtitle size', 'اندازه زیرنویس')),
                    subtitle: Slider(
                      value: prefs.subtitleFontSize.clamp(12, 40),
                      min: 12,
                      max: 40,
                      onChanged: (v) async {
                        await _app!.updateSettings(
                          prefs.copyWith(subtitleFontSize: v),
                        );
                        if (sheetContext.mounted) update(() {});
                      },
                    ),
                  ),
                  ListTile(
                    title: Text(
                      tr(
                        context,
                        'Subtitle & audio timing',
                        'هماهنگی زیرنویس و صدا',
                      ),
                    ),
                    subtitle: Text(
                      '${prefs.subtitleDelay}s / ${prefs.audioDelay}s',
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Subtitle -0.5s',
                          onPressed: () async {
                            await _app!.updateSettings(
                              prefs.copyWith(
                                subtitleDelay: prefs.subtitleDelay - .5,
                              ),
                            );
                            await _applyDelays();
                            if (sheetContext.mounted) update(() {});
                          },
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          tooltip: 'Subtitle +0.5s',
                          onPressed: () async {
                            await _app!.updateSettings(
                              prefs.copyWith(
                                subtitleDelay: prefs.subtitleDelay + .5,
                              ),
                            );
                            await _applyDelays();
                            if (sheetContext.mounted) update(() {});
                          },
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: Text(
                      tr(context, 'Audio only', 'فقط صدا (در پیش‌زمینه)'),
                    ),
                    value: _audioOnly,
                    onChanged: (v) {
                      _guard(_setAudioOnly(v));
                      update(() {});
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.screen_rotation),
                    title: Text(tr(context, 'Rotate player', 'چرخاندن صفحه')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _guard(
                        SystemChrome.setPreferredOrientations(
                          MediaQuery.orientationOf(context) ==
                                  Orientation.portrait
                              ? [
                                  DeviceOrientation.landscapeLeft,
                                  DeviceOrientation.landscapeRight,
                                ]
                              : [DeviceOrientation.portraitUp],
                        ),
                      );
                    },
                  ),
                  if (MediaPlatform.supported) ...[
                    ListTile(
                      leading: const Icon(Icons.brightness_6_outlined),
                      title: Text(tr(context, 'Brightness', 'روشنایی')),
                      subtitle: Slider(
                        value: _brightness,
                        onChanged: (v) {
                          update(() => _brightness = v);
                          _guard(
                            MediaPlatform.invoke<void>('setBrightness', {
                              'value': v,
                            }),
                          );
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.volume_up_outlined),
                      title: Text(tr(context, 'System volume', 'صدای دستگاه')),
                      subtitle: Slider(
                        value: _volume,
                        onChanged: (v) {
                          update(() => _volume = v);
                          _guard(_setVolume(v));
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.open_in_new),
                      title: Text(
                        tr(context, 'Open external player', 'پخش‌کننده خارجی'),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _guard(_externalPlayer());
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
    _settingsOpen = false;
    _scheduleHide();
  }

  double _brightness = .6, _volume = .5;
  Future<void> _remoteSubtitles() async {
    final list = await _app!.api.subtitles(
      _episode == null ? 'movie' : 'episode',
      _episode?.id ?? widget.title.id,
    );
    if (!mounted) return;
    if (list.isEmpty) {
      _notice(
        tr(
          context,
          'No subtitles returned by the service',
          'سرویس زیرنویسی برنگرداند',
        ),
      );
      return;
    }
    final groups = subtitleGroups(list);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ListView(
        children: [
          for (final group in groups.entries)
            ExpansionTile(
              title: Text(group.key),
              initiallyExpanded: groups.length == 1,
              children: [
                for (final variant in group.value)
                  ListTile(
                    title: Text(variant.label),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _guard(_loadRemoteSubtitle(variant));
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _loadRemoteSubtitle(SubtitleVariant variant) async {
    final episode = _episode?.id;
    final source = _source.url;
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final cancel = CancelToken();
    try {
      final response = await client.get<List<int>>(
        variant.url,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancel,
        onReceiveProgress: (count, total) {
          if (count > 8 * 1024 * 1024) cancel.cancel('Subtitle exceeds 8 MB');
        },
      );
      if (!mounted ||
          !_lifecycle.ownsSystem ||
          episode != _episode?.id ||
          source != _source.url) {
        return;
      }
      final bytes = response.data ?? const <int>[];
      if (bytes.length > 8 * 1024 * 1024) {
        throw StateError('Subtitle exceeds 8 MB');
      }
      final text = decodeSubtitle(bytes);
      await _selectSubtitleTrack(
        SubtitleTrack.data(
          text,
          title: variant.label,
          language: variant.language,
        ),
        sourceUrl: variant.url,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class PlayerSurfaceGestures extends StatelessWidget {
  const PlayerSurfaceGestures({
    super.key,
    required this.locked,
    required this.onAction,
  });
  final bool locked;
  final void Function(String) onAction;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: locked ? null : () => onAction('controls'),
    onDoubleTap: locked ? null : () => onAction('fullscreen'),
    onScaleUpdate: locked
        ? null
        : (details) {
            if (details.pointerCount >= 2 && details.scale > 1.12) {
              onAction('fill');
            }
            if (details.pointerCount >= 2 && details.scale < .88) {
              onAction('contain');
            }
          },
    child: const SizedBox.expand(),
  );
}

/// Keyboard and hover handling shared by the player and its controls.
class PlayerInteraction extends StatelessWidget {
  const PlayerInteraction({
    super.key,
    required this.locked,
    required this.controlsVisible,
    required this.onAction,
    required this.child,
  });
  final bool locked, controlsVisible;
  final void Function(String) onAction;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    void action(String value) {
      if (!locked) onAction(value);
    }

    return CallbackShortcuts(
      bindings: {
        for (final entry in <LogicalKeyboardKey, String>{
          LogicalKeyboardKey.space: 'toggle',
          LogicalKeyboardKey.keyK: 'toggle',
          LogicalKeyboardKey.mediaPlayPause: 'toggle',
          LogicalKeyboardKey.mediaPlay: 'play',
          LogicalKeyboardKey.mediaPause: 'pause',
          LogicalKeyboardKey.mediaStop: 'stop',
          LogicalKeyboardKey.keyM: 'mute',
          LogicalKeyboardKey.keyF: 'fullscreen',
          LogicalKeyboardKey.escape: 'exitFullscreen',
          LogicalKeyboardKey.arrowLeft: 'back',
          LogicalKeyboardKey.arrowRight: 'forward',
          LogicalKeyboardKey.keyJ: 'back',
          LogicalKeyboardKey.keyL: 'forward',
          LogicalKeyboardKey.arrowUp: 'volumeUp',
          LogicalKeyboardKey.arrowDown: 'volumeDown',
          LogicalKeyboardKey.mediaTrackNext: 'next',
          LogicalKeyboardKey.mediaTrackPrevious: 'previous',
          LogicalKeyboardKey.keyN: 'next',
          LogicalKeyboardKey.keyP: 'previous',
          LogicalKeyboardKey.keyS: 'subtitles',
        }.entries)
          SingleActivator(entry.key): () => action(entry.value),
      },
      child: Focus(
        autofocus: true,
        child: MouseRegion(
          cursor: !controlsVisible && !locked
              ? SystemMouseCursors.none
              : MouseCursor.defer,
          onHover: (_) => action('show'),
          child: child,
        ),
      ),
    );
  }
}
