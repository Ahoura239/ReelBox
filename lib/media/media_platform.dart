import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Captures Android controls on entry and restores the activity's brightness
/// override on exit. System volume is intentionally not restored.
class PlayerSystemControls {
  double brightness = .5, volume = .5;
  // The activity baseline belongs to the shared player-control session. A
  // replacement route must not adopt the previous route's override as baseline.
  static double? _originalBrightness;
  Future<void> capture() async {
    if (!MediaPlatform.supported) return;
    final original = await MediaPlatform.invoke<double>('getBrightness');
    final effective = original != null && original >= 0
        ? original
        : await MediaPlatform.invoke<double>('getEffectiveBrightness');
    final currentVolume = await MediaPlatform.invoke<double>('getVolume');
    _originalBrightness ??= original ?? -1;
    if (effective != null && effective.isFinite) {
      brightness = effective.clamp(0, 1);
    }
    if (currentVolume != null && currentVolume.isFinite) {
      volume = currentVolume.clamp(0, 1);
    }
  }

  Future<void> restore() async {
    final original = _originalBrightness;
    _originalBrightness = null;
    if (original != null && MediaPlatform.supported) {
      await MediaPlatform.invoke<void>('setBrightness', {'value': original});
    }
  }
}

/// Android channel implemented by MainActivity; no synthetic platform success.
class MediaPlatform {
  static const channel = MethodChannel('org.reelbox/media');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<T?> invoke<T>(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (!supported) {
      throw UnsupportedError('This control is available on Android only.');
    }
    return channel.invokeMethod<T>(method, args);
  }

  static Future<bool> enterPip() async =>
      await invoke<bool>('enterPip') ?? false;
  static Future<void> setActive(bool active) async {
    if (supported) await invoke<void>('setPlayerActive', {'active': active});
  }

  static Future<void> openExternal(
    String url, {
    String packageName = 'ask',
    String? title,
    String? subtitleUrl,
    Duration? position,
  }) async {
    final ok = await invoke<bool>('openExternal', {
      'url': url,
      'packageName': packageName,
      'title': ?title,
      'subtitleUrl': ?subtitleUrl,
      if (position != null) 'positionMs': position.inMilliseconds,
    });
    if (ok != true) {
      throw StateError(
        'No installed external video player can open this source.',
      );
    }
  }
}

/// Single-owner notification/Cast bridge. The local media_kit player remains the
/// decoder; the Android foreground service never opens a second audio stream.
class PlayerNativeSession {
  PlayerNativeSession({
    required this.invoke,
    required this.local,
    required this.media,
    required this.isPlaying,
    required this.isCurrent,
    this.changed,
    this.failure,
    this.prepareMedia,
    this.revokeMedia,
    this._castRequested = false,
  });
  Future<dynamic> Function(String, Map<String, dynamic>?) invoke;
  final Future<void> Function(String, Duration?) local;
  final Map<String, dynamic> Function() media;
  final bool Function() isPlaying, isCurrent;
  final void Function()? changed;
  final void Function(String)? failure;
  final Future<Map<String, dynamic>> Function()? prepareMedia;
  final Future<void> Function()? revokeMedia;
  bool _castRequested;
  static PlayerNativeSession? _owner;
  bool _released = false,
      _loading = false,
      _background = false,
      _stopped = false;
  bool _castAttempted = false;
  Future<void>? _loadTail;
  bool? _loadPlayState;
  int _castRevision = 0;
  int? _disconnectedRevision;
  bool casting = false, connected = false, playing = false, inPip = false;
  Duration position = Duration.zero, duration = Duration.zero;
  String deviceName = '';
  bool get active => !_released && identical(_owner, this) && isCurrent();
  void claim() {
    _owner = this;
    MediaPlatform.channel.setMethodCallHandler(handle);
  }

  void release() {
    _released = true;
    _disconnectedRevision = null;
    _castRevision++;
    unawaited(_revoke().catchError((Object _) {}));
    if (identical(_owner, this)) {
      _owner = null;
      MediaPlatform.channel.setMethodCallHandler(null);
    }
  }

  Future<void> handle(MethodCall call) async {
    if (!active) return;
    if (call.method == 'pipChanged') {
      inPip = call.arguments == true;
      changed?.call();
      return;
    }
    if (call.arguments is! Map) return;
    final args = Map<String, dynamic>.from(call.arguments as Map);
    if (call.method == 'mediaAction') {
      final action = args['action'];
      if (action is String &&
          const [
            'play',
            'pause',
            'seek',
            'stop',
            'next',
            'previous',
          ].contains(action)) {
        final ms = args['positionMs'];
        if (action == 'seek' && (ms is! num || !ms.isFinite || ms < 0)) return;
        await command(
          action,
          position: ms is num ? Duration(milliseconds: ms.toInt()) : null,
        );
      }
    } else if (call.method == 'castChanged') {
      final wasConnected = connected;
      connected = args['connected'] == true;
      deviceName = args['deviceName'] is String
          ? args['deviceName'] as String
          : deviceName;
      if (!connected) {
        _castAttempted = false;
        if (wasConnected) _disconnectedRevision = _castRevision;
        _castRevision++;
        await _revoke();
        if (casting) {
          final resume = playing;
          casting = false;
          await local('seek', position);
          if (!active) return;
          await local(resume ? 'play' : 'pause', null);
        }
      } else if (_castRequested && !casting && !_loading && !_castAttempted) {
        await loadCast();
      } else if (casting) {
        playing = args['playing'] == true;
        final p = args['positionMs'], d = args['durationMs'];
        if (p is num && p.isFinite && p >= 0) {
          position = Duration(milliseconds: p.toInt());
        }
        if (d is num && d.isFinite && d >= 0) {
          duration = Duration(milliseconds: d.toInt());
        }
      }
      if (active) changed?.call();
    }
  }

  /// Cancel snapshots synchronously, before a source/subtitle change awaits.
  /// This does not grant sharing consent or enqueue a replacement transfer.
  Future<void> invalidateCastMedia() {
    _castRevision++;
    _disconnectedRevision = null;
    return _revoke();
  }

  Future<void> loadCast() {
    if (!active) return Future<void>.value();
    _disconnectedRevision = null;
    _castAttempted = true;
    _castRequested = true;
    final revision = ++_castRevision;
    _loadPlayState ??= isPlaying();
    final previous = _loadTail;
    final work = previous == null
        ? Future<void>.microtask(() => _runCastLoad(revision))
        : previous.then((_) => _runCastLoad(revision));
    late final Future<void> tail;
    tail = work.catchError((Object _) {}).whenComplete(() {
      if (identical(_loadTail, tail)) {
        _loadTail = null;
        _loadPlayState = null;
      }
    });
    _loadTail = tail;
    return work;
  }

  Future<void> _runCastLoad(int revision) async {
    if (!active || revision != _castRevision || !connected) return;
    _loading = true;
    final wasPlaying = _loadPlayState ?? isPlaying();
    var paused = false;
    try {
      final payload = Map<String, dynamic>.from(
        prepareMedia == null ? media() : await prepareMedia!(),
      );
      if (!active || revision != _castRevision) {
        await _revoke();
        return;
      }
      await local('pause', null);
      paused = true;
      if (!active || revision != _castRevision) {
        await _revoke();
        await _restoreDisconnectedLoad(revision);
        return;
      }
      final ok = await invoke('castLoad', payload);
      if (!active) return;
      if (revision != _castRevision) {
        if (_stopped) await invoke('castCommand', {'action': 'stop'});
        await _revoke();
        await _restoreDisconnectedLoad(revision);
        return;
      }
      if (ok != true) throw StateError('Cast load rejected');
      casting = true;
      playing = _loadPlayState ?? wasPlaying;
      position = Duration(
        milliseconds: (payload['positionMs'] as num?)?.toInt() ?? 0,
      );
      if (!playing) await invoke('castCommand', {'action': 'pause'});
      // A remote session must not also advertise a local background session.
      if (_background) {
        await invoke('backgroundPlaybackStop', null);
        _background = false;
      }
    } catch (error) {
      await _revoke();
      if (!active || revision != _castRevision) {
        if (paused) await _restoreDisconnectedLoad(revision);
        return;
      }
      casting = false;
      if (paused) {
        await local((_loadPlayState ?? wasPlaying) ? 'play' : 'pause', null);
      }
      if (active && revision == _castRevision) {
        failure?.call(
          error is FormatException || error is UnsupportedError
              ? 'This media or subtitle format cannot be shared with the Cast device. Local playback restored.'
              : 'Could not load this video on the Cast device. Local playback restored.',
        );
      }
    } finally {
      _loading = false;
      if (active) changed?.call();
    }
  }

  Future<void> _revoke() async {
    await revokeMedia?.call();
  }

  Future<void> _restoreDisconnectedLoad(int revision) async {
    // Only disconnect may restore an interrupted transfer. A newer media load,
    // stop or owner must never be undone by the old decoder pause completing.
    if (active &&
        !connected &&
        !_stopped &&
        _disconnectedRevision == revision) {
      await local((_loadPlayState ?? isPlaying()) ? 'play' : 'pause', null);
    }
  }

  Future<void> command(
    String action, {
    Duration? position,
    double? value,
  }) async {
    if (!active) return;
    if (_loadTail != null && (action == 'play' || action == 'pause')) {
      _loadPlayState = action == 'play';
    }
    if (action == 'play') _stopped = false;
    if (action == 'stop') {
      _stopped = true;
      _disconnectedRevision = null;
      _castRequested = false;
      _castRevision++;
      await stopBackground();
      if (!active) return;
      try {
        if (casting) await invoke('castCommand', {'action': 'stop'});
        await local('stop', null);
      } finally {
        casting = false;
        await _revoke();
        if (active) changed?.call();
      }
      return;
    }
    if (casting &&
        const ['play', 'pause', 'seek', 'stop', 'volume'].contains(action)) {
      await invoke('castCommand', {
        'action': action,
        if (position != null) 'positionMs': position.inMilliseconds,
        'value': ?value,
      });
    } else {
      await local(action, position);
    }
  }

  Future<bool> picker() async {
    if (!active) return false;
    _castRequested = true;
    return await invoke('castShowPicker', null) == true;
  }

  Future<void> disconnect() async {
    if (!active) return;
    _castRequested = false;
    await invoke('castDisconnect', null);
    if (active) {
      await handle(const MethodCall('castChanged', {'connected': false}));
    }
  }

  Future<void> refreshCast() async {
    if (!active) return;
    final state = await invoke('castGetState', null);
    if (active && state is Map) await handle(MethodCall('castChanged', state));
  }

  Future<void> background({
    required bool enabled,
    required bool playing,
    required Duration position,
    required Duration duration,
  }) async {
    if (!active) return;
    if (!enabled || casting || _stopped) {
      if (_background) {
        await invoke('backgroundPlaybackStop', null);
        _background = false;
      }
      return;
    }
    await invoke(
      _background ? 'backgroundPlaybackUpdate' : 'backgroundPlayback',
      {
        if (!_background) 'enabled': true,
        'title': media()['title'] ?? '',
        'playing': playing,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
      },
    );
    _background = true;
  }

  Future<void> stopBackground() async {
    if (_background) {
      await invoke('backgroundPlaybackStop', null);
      _background = false;
    }
  }
}
