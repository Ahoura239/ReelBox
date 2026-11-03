import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/media/player_page.dart';
import 'package:reelbox/media/media_platform.dart';
import 'package:reelbox/media/cast_media_share.dart';
import 'package:reelbox/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Streams implements PlayerStream {
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final playingEvents = StreamController<bool>.broadcast();
  final completedEvents = StreamController<bool>.broadcast();
  @override
  Stream<Duration> get position => positions.stream;
  @override
  Stream<Duration> get duration => durations.stream;
  @override
  Stream<bool> get playing => playingEvents.stream;
  @override
  Stream<bool> get completed => completedEvents.stream;
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<Tracks> get tracks => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  Future<void> close() async {
    await positions.close();
    await durations.close();
    await playingEvents.close();
    await completedEvents.close();
  }
}

class _Engine implements Player {
  @override
  final _Streams stream = _Streams();
  @override
  PlayerState get state =>
      PlayerState(tracks: Tracks(subtitle: subtitleTracks));
  List<SubtitleTrack> subtitleTracks = const [
    SubtitleTrack('auto', null, null),
    SubtitleTrack('no', null, null),
  ];
  final calls = <String>[];
  final opens = <Media>[];
  @override
  PlatformPlayer? platform;
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final m = playable as Media;
    opens.add(m);
    calls.add('open:$play');
  }

  @override
  Future<void> play() async {
    calls.add('play');
    stream.playingEvents.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    stream.playingEvents.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inSeconds}');
    stream.positions.add(position);
  }

  @override
  Future<void> setRate(double value) async {
    calls.add('rate:$value');
  }

  @override
  Future<void> setVolume(double value) async {
    calls.add('volume:$value');
  }

  @override
  Future<void> setVideoTrack(VideoTrack value) async {
    calls.add('video:${value.id}');
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack value) async {
    calls.add('subtitle:${value.id}');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'persisted Stretch dispatches actual fill geometry instead of contain',
    (tester) async {
      final app = AppState();
      final engine = _Engine();
      final fits = <BoxFit>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await engine.stream.close();
        app.dispose();
      });
      await app.updateSettings(AppSettings(videoFit: 'fill'));
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            home: PlayerPage(
              title: const TitleRecord(id: 82, title: 'Film'),
              source: const MediaSource(url: 'https://media.test/film.mp4'),
              playerFactory: () => engine,
              videoControllerFactory: (_) => null,
              videoSurfaceBuilder: (fit) {
                fits.add(fit);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(fits.last, BoxFit.fill);
      await tester.tap(find.byTooltip('Fit or fill'));
      await tester.pump();
      expect(fits.last, BoxFit.cover);
      await tester.tap(find.byTooltip('Fit or fill'));
      await tester.pump();
      expect(fits.last, BoxFit.contain);
    },
  );
  testWidgets(
    'actual subtitle track picker updates active Cast text and clears stale external data',
    (tester) async {
      final app = AppState();
      final engine = _Engine();
      const aText = '1\n00:00:00,000 --> 00:00:01,000\nExternal A';
      const bText = '1\n00:00:00,000 --> 00:00:01,000\nExternal B';
      engine.subtitleTracks = [
        SubtitleTrack.data(aText, title: 'External A'),
        const SubtitleTrack('2', 'Embedded B', 'en'),
        SubtitleTrack.no(),
        SubtitleTrack.data(bText, title: 'External B'),
      ];
      final sharedText = <String?>[];
      var closed = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MediaPlatform.channel,
        (call) async => switch (call.method) {
          'getBrightness' => -1.0,
          'getEffectiveBrightness' => 0.6,
          'getVolume' => 0.5,
          'castGetState' => {
            'connected': true,
            'deviceName': 'Fixture receiver',
          },
          'castLoad' => true,
          _ => null,
        },
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await engine.stream.close();
        app.dispose();
      });
      await app.updateSettings(AppSettings());
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            home: PlayerPage(
              title: const TitleRecord(id: 81, title: 'Film'),
              source: const MediaSource(url: 'https://media.test/film.mp4'),
              playerFactory: () => engine,
              videoControllerFactory: (_) => null,
              castShareFactory:
                  ({required payload, localFile, subtitleText}) async {
                    sharedText.add(subtitleText);
                    return CastMediaLease(
                      payload: payload,
                      onClose: () async {
                        closed++;
                      },
                    );
                  },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      Future<void> choose(String name) async {
        await tester.tap(find.byTooltip('Player settings'));
        await tester.pumpAndSettle();
        final track = engine.subtitleTracks.firstWhere(
          (track) => (track.title ?? track.language ?? track.id) == name,
        );
        final target = find.byKey(ValueKey(track));
        await tester.scrollUntilVisible(
          target,
          300,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await choose('External A');
      await tester.tap(find.byTooltip('Cast to device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cast this video'));
      await tester.pumpAndSettle();
      expect(sharedText, [aText]);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await choose('Embedded B');
      expect(sharedText, [aText, null]);
      expect(
        find.text(
          'Embedded subtitles cannot be shared; Cast continues without them',
        ),
        findsOneWidget,
      );
      await choose('no');
      expect(app.prefs.subtitleEnabled, false);
      expect(sharedText, [aText, null, null]);
      await choose('External B');
      expect(sharedText.last, bText);
      expect(app.prefs.subtitleEnabled, true);
      expect(closed, 3);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'offline player explicitly hands Cast a sharing lease and revokes it on exit',
    (tester) async {
      final app = AppState();
      final engine = _Engine();
      var prepared = 0, closed = 0;
      String? preparedFile;
      final loads = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MediaPlatform.channel,
        (call) async {
          return switch (call.method) {
            'getBrightness' => -1.0,
            'getEffectiveBrightness' => 0.6,
            'getVolume' => 0.5,
            'castGetState' => {
              'connected': true,
              'deviceName': 'Synthetic receiver',
            },
            'castLoad' => (() {
              loads.add(call.arguments as Map);
              return true;
            })(),
            'castShowPicker' => true,
            _ => null,
          };
        },
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await engine.stream.close();
        app.dispose();
      });
      await app.updateSettings(AppSettings());
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            home: PlayerPage(
              title: const TitleRecord(id: 42, title: 'Synthetic offline film'),
              source: const MediaSource(url: 'https://media.test/original.mp4'),
              localFile: '/selected/synthetic.mp4',
              playerFactory: () => engine,
              videoControllerFactory: (_) => null,
              castShareFactory:
                  ({required payload, localFile, subtitleText}) async {
                    prepared++;
                    preparedFile = localFile;
                    return CastMediaLease(
                      payload: {
                        ...payload,
                        'url': 'http://127.0.0.1:1234/synthetic/media.mp4',
                      },
                      onClose: () async {
                        closed++;
                      },
                    );
                  },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        prepared,
        0,
        reason: 'Opening a page must not start local sharing',
      );
      await tester.tap(find.byTooltip('Cast to device'));
      await tester.pumpAndSettle();
      expect(
        prepared,
        0,
        reason: 'Choosing a receiver menu must not start sharing',
      );
      await tester.tap(find.text('Cast this video'));
      await tester.pump(const Duration(milliseconds: 100));
      // Native receiver connection callback, not a fabricated successful load.
      final completed = Completer<void>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        MediaPlatform.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('castChanged', {
            'connected': true,
            'deviceName': 'Synthetic receiver',
          }),
        ),
        (_) => completed.complete(),
      );
      await tester.pump();
      await completed.future;
      await tester.pump();
      expect(prepared, 1);
      expect(preparedFile, '/selected/synthetic.mp4');
      expect(Uri.parse(loads.single['url'] as String).scheme, 'http');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(closed, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  for (final change in [
    'quality',
    'episode',
    'subtitles',
    'stop',
    'new owner',
  ]) {
    testWidgets(
      'pending page Cast lease is invalidated by actual $change change',
      (tester) async {
        final app = AppState();
        final engine = _Engine();
        final newerEngine = _Engine();
        final prepared = Completer<CastMediaLease>();
        final loads = <Map>[];
        final snapshots = <Map<String, dynamic>>[];
        var closed = 0;
        const a = MediaSource(url: 'https://media.test/a.mp4', quality: '720p');
        const b = MediaSource(
          url: 'https://media.test/b.mp4',
          quality: '1080p',
        );
        const one = EpisodeRecord(id: 1, title: 'First', sources: [a, b]);
        const two = EpisodeRecord(id: 2, title: 'Second', sources: [b]);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MediaPlatform.channel,
          (call) async {
            return switch (call.method) {
              'getBrightness' => -1.0,
              'getEffectiveBrightness' => 0.6,
              'getVolume' => 0.5,
              'castGetState' => {'connected': true, 'deviceName': 'Receiver'},
              'castLoad' => (() {
                loads.add(call.arguments as Map);
                return true;
              })(),
              _ => null,
            };
          },
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await engine.stream.close();
          await newerEngine.stream.close();
          app.dispose();
        });
        await app.updateSettings(AppSettings());
        await tester.pumpWidget(
          AppScope(
            state: app,
            child: MaterialApp(
              home: PlayerPage(
                title: const TitleRecord(id: 43, title: 'Series'),
                source: a,
                episode: one,
                playlist: const [one, two],
                playerFactory: () => engine,
                videoControllerFactory: (_) => null,
                castShareFactory:
                    ({required payload, localFile, subtitleText}) async {
                      snapshots.add({...payload, 'selectedText': subtitleText});
                      if (snapshots.length == 1) return prepared.future;
                      return CastMediaLease(
                        payload: payload,
                        onClose: () async {},
                      );
                    },
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(snapshots, isEmpty);
        await tester.tap(find.byTooltip('Cast to device'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cast this video'));
        await tester.pump();
        expect(snapshots.single['url'], a.url);
        // Dismiss the actual sheet while its explicit load is still pending.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        if (change == 'quality') {
          await tester.tap(find.text('1080p'));
        } else if (change == 'episode') {
          await tester.tap(find.byTooltip('Next episode'));
        } else if (change == 'subtitles') {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        } else if (change == 'stop') {
          await tester.sendKeyEvent(LogicalKeyboardKey.mediaStop);
        } else {
          await tester.pumpWidget(
            AppScope(
              state: app,
              child: MaterialApp(
                home: PlayerPage(
                  key: const ValueKey('new owner'),
                  title: const TitleRecord(id: 44, title: 'New owner'),
                  source: b,
                  playerFactory: () => newerEngine,
                  videoControllerFactory: (_) => null,
                ),
              ),
            ),
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
        if (change == 'quality' || change == 'episode') {
          expect(engine.opens.last.uri, b.url);
        }
        if (change == 'subtitles') expect(app.prefs.subtitleEnabled, false);
        prepared.complete(
          CastMediaLease(
            payload: {'url': a.url, 'title': 'Obsolete'},
            onClose: () async {
              closed++;
            },
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          loads,
          isEmpty,
          reason:
              'A malicious late lease must not load its captured old payload',
        );
        expect(closed, 1);
        expect(find.textContaining('Could not load this video'), findsNothing);
        if (change == 'quality' ||
            change == 'episode' ||
            change == 'subtitles') {
          // Cancellation does not silently re-share; another explicit action can.
          expect(snapshots, hasLength(1));
          await tester.tap(find.byTooltip('Cast to device'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cast this video'));
          await tester.pumpAndSettle();
          expect(loads.single['url'], change == 'subtitles' ? a.url : b.url);
          expect(snapshots, hasLength(2));
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaPlatform.channel, (call) async {
          return switch (call.method) {
            'getBrightness' => -1.0,
            'getEffectiveBrightness' => 0.6,
            'getVolume' => 0.5,
            'castGetState' => <String, dynamic>{'connected': false},
            _ => null,
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaPlatform.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  testWidgets(
    'real player controls dispatch to engine and persist fit/subtitle options',
    (tester) async {
      final app = AppState();
      final engine = _Engine();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await engine.stream.close();
        app.dispose();
      });
      await app.updateSettings(AppSettings(playbackSpeed: 1.75));
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            home: PlayerPage(
              title: const TitleRecord(id: 1, title: 'Film'),
              source: const MediaSource(url: 'https://media.test/film.mp4'),
              playerFactory: () => engine,
              videoControllerFactory: (_) => null,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The native decoder is replaced, not the actual player control dispatch.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'engine calls: ${engine.calls}; text: ${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
      );
      expect(engine.calls, containsAllInOrder(['open:false', 'rate:1.75']));
      engine.stream.positions.add(const Duration(seconds: 30));
      engine.stream.durations.add(const Duration(seconds: 600));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(engine.calls, contains('seek:40'));
      expect(engine.calls, contains('volume:0.0'));
      await tester.tap(find.byTooltip('Fit or fill'));
      await tester.pump(const Duration(milliseconds: 100));
      // The native decoder is replaced, not the actual player control dispatch.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'engine calls: ${engine.calls}; text: ${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
      );
      expect(app.prefs.videoFit, 'cover');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump(const Duration(milliseconds: 100));
      // The native decoder is replaced, not the actual player control dispatch.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'engine calls: ${engine.calls}; text: ${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
      );
      expect(app.prefs.subtitleEnabled, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byTooltip('Player settings'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(engine.calls, containsAllInOrder(['play', 'pause']));
      expect(find.byTooltip('Player settings'), findsOneWidget);
    },
  );
  testWidgets(
    'resume retains history, rewinds dispatch, and next updates episode context',
    (tester) async {
      final app = AppState();
      final engine = _Engine();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await engine.stream.close();
        app.dispose();
      });
      const title = TitleRecord(id: 2, title: 'Series');
      const one = EpisodeRecord(
        id: 11,
        title: 'Episode one',
        sources: [MediaSource(url: 'https://media.test/1.mp4')],
      );
      const two = EpisodeRecord(
        id: 12,
        title: 'Episode two',
        sources: [MediaSource(url: 'https://media.test/2.mp4')],
      );
      await app.updateSettings(AppSettings(resumeRewindSeconds: 5));
      await app.recordWatch(
        title,
        episodeId: 11,
        episodeTitle: one.title,
        positionSeconds: 60,
        durationSeconds: 600,
        sourceUrl: one.sources.single.url,
      );
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            home: PlayerPage(
              title: title,
              source: one.sources.single,
              episode: one,
              playlist: const [one, two],
              playerFactory: () => engine,
              videoControllerFactory: (_) => null,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The native decoder is replaced, not the actual player control dispatch.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'engine calls: ${engine.calls}; text: ${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
      );
      expect(engine.opens.single.start, const Duration(seconds: 55));
      expect(app.history.single.positionSeconds, 60);
      engine.stream.completedEvents.add(true);
      await tester.pump(const Duration(milliseconds: 100));
      // The native decoder is replaced, not the actual player control dispatch.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'engine calls: ${engine.calls}; text: ${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
      );
      expect(engine.opens.last.uri, two.sources.single.url);
      expect(find.text('Episode two'), findsOneWidget);
      expect(app.history.single.positionSeconds, 60);
    },
  );
}
