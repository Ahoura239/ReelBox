import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> actions;
  late List<MethodCall> native;
  late PlayerNativeSession session;
  setUp(() {
    actions = [];
    native = [];
    session = PlayerNativeSession(
      invoke: (method, args) async {
        native.add(MethodCall(method, args));
        return true;
      },
      local: (action, position) async {
        actions.add('$action:${position?.inMilliseconds}');
      },
      media: () => {
        'url': 'https://media.test/v.mp4',
        'title': 'Episode 2',
        'positionMs': 12000,
        'subtitleUrl': 'https://media.test/fa.srt',
      },
      castRequested: true, // These protocol tests start with a user's request.
      isPlaying: () => true,
      isCurrent: () => true,
    );
    session.claim();
  });
  tearDown(() => session.release());
  test(
    'media actions dispatch actual local controls and reject unknown actions',
    () async {
      await session.handle(
        const MethodCall('mediaAction', {'action': 'seek', 'positionMs': 4500}),
      );
      await session.handle(const MethodCall('mediaAction', {'action': 'next'}));
      await session.handle(
        const MethodCall('mediaAction', {'action': 'invented'}),
      );
      expect(actions, ['seek:4500', 'next:null']);
    },
  );
  test('Cast transfer pauses decoder and routes controls remotely until disconnect', () async {
    await session.handle(
      const MethodCall('castChanged', {'connected': true, 'deviceName': 'TV'}),
    );
    expect(session.casting, true);
    expect(actions, ['pause:null']);
    expect(native.single.method, 'castLoad');
    expect(native.single.arguments['positionMs'], 12000);
    expect(native.single.arguments['subtitleUrl'], 'https://media.test/fa.srt');
    await session.command('seek', position: const Duration(seconds: 30));
    expect(native.last.method, 'castCommand');
    expect(native.last.arguments, {'action': 'seek', 'positionMs': 30000});
    await session.handle(
      const MethodCall('castChanged', {
        'connected': true,
        'playing': true,
        'positionMs': 33000,
        'durationMs': 60000,
      }),
    );
    await session.handle(const MethodCall('castChanged', {'connected': false}));
    expect(actions, ['pause:null', 'seek:33000', 'play:null']);
    expect(session.casting, false);
  });
  test(
    'failed Cast load restores local playback and leaves no remote mode',
    () async {
      session.invoke = (method, args) async => false;
      await session.handle(
        const MethodCall('castChanged', {'connected': true}),
      );
      expect(session.casting, false);
      expect(actions, ['pause:null', 'play:null']);
    },
  );
  test('failed Cast load is not retried by repeated connected polls', () async {
    session.invoke = (method, args) async {
      native.add(MethodCall(method, args));
      return false;
    };
    await session.handle(const MethodCall('castChanged', {'connected': true}));
    await session.handle(const MethodCall('castChanged', {'connected': true}));
    await session.handle(const MethodCall('castChanged', {'connected': true}));
    expect(native.where((call) => call.method == 'castLoad'), hasLength(1));
    expect(actions, ['pause:null', 'play:null']);
    // A real reconnect may retry once; ordinary state polling may not.
    await session.handle(const MethodCall('castChanged', {'connected': false}));
    await session.handle(const MethodCall('castChanged', {'connected': true}));
    expect(native.where((call) => call.method == 'castLoad'), hasLength(2));
  });
  test(
    'old owner cannot clear new handler or dispatch pending action',
    () async {
      final old = session;
      final writes = <String>[];
      final newer = PlayerNativeSession(
        invoke: old.invoke,
        local: (a, p) async => writes.add(a),
        media: () => {},
        isPlaying: () => false,
        isCurrent: () => true,
      )..claim();
      old.release();
      await old.handle(const MethodCall('mediaAction', {'action': 'play'}));
      await newer.handle(const MethodCall('pipChanged', true));
      await newer.handle(const MethodCall('mediaAction', {'action': 'pause'}));
      expect(actions, isEmpty);
      expect(writes, ['pause']);
      expect(newer.inPip, true);
      newer.release();
    },
  );
  test(
    'disconnect during pending load cannot revive stale Cast mode',
    () async {
      final load = Completer<bool>();
      session.invoke = (method, args) => load.future;
      final pending = session.handle(
        const MethodCall('castChanged', {'connected': true}),
      );
      await Future<void>.delayed(Duration.zero);
      await session.handle(
        const MethodCall('castChanged', {'connected': false}),
      );
      load.complete(true);
      await pending;
      expect(session.casting, false);
      expect(actions, ['pause:null', 'play:null']);
    },
  );
  for (final intent in [true, false]) {
    test('disconnect during awaited local pause restores latest intent $intent', () async {
      final pause = Completer<void>();
      var firstPause = true;
      final writes = <String>[];
      final pendingSession = PlayerNativeSession(
        castRequested: true,
        invoke: (method, _) async {
          writes.add(method);
          return true;
        },
        local: (action, _) async {
          writes.add(action);
          if (action == 'pause' && firstPause) {
            firstPause = false;
            await pause.future;
          }
        },
        media: () => {'url': 'https://media.test/current.mp4'},
        isPlaying: () => true,
        isCurrent: () => true,
      )..claim();
      addTearDown(pendingSession.release);
      final load = pendingSession.handle(
        const MethodCall('castChanged', {'connected': true}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(writes, ['pause']);
      await pendingSession.command(intent ? 'play' : 'pause');
      await pendingSession.handle(
        const MethodCall('castChanged', {'connected': false}),
      );
      // Repeated disconnected polling must not discard the restoration reason.
      await pendingSession.handle(
        const MethodCall('castChanged', {'connected': false}),
      );
      pause.complete();
      await load;
      expect(writes, [
        'pause',
        intent ? 'play' : 'pause',
        intent ? 'play' : 'pause',
      ]);
      expect(pendingSession.casting, false);
    });
  }
  for (final cancellation in ['stop', 'release', 'new owner', 'new load']) {
    test(
      'awaited pause cancellation cannot resume after $cancellation',
      () async {
        final pause = Completer<void>();
        var firstPause = true;
        final writes = <String>[];
        final pendingSession = PlayerNativeSession(
          castRequested: true,
          invoke: (method, _) async {
            writes.add(method);
            return true;
          },
          local: (action, _) async {
            writes.add(action);
            if (action == 'pause' && firstPause) {
              firstPause = false;
              await pause.future;
            }
          },
          media: () => {'url': 'https://media.test/current.mp4'},
          isPlaying: () => true,
          isCurrent: () => true,
        )..claim();
        addTearDown(pendingSession.release);
        final load = pendingSession.handle(
          const MethodCall('castChanged', {'connected': true}),
        );
        await Future<void>.delayed(Duration.zero);
        await pendingSession.handle(
          const MethodCall('castChanged', {'connected': false}),
        );
        Future<void>? newerLoad;
        if (cancellation == 'stop') {
          await pendingSession.command('stop');
        } else if (cancellation == 'release') {
          pendingSession.release();
        } else if (cancellation == 'new load') {
          newerLoad = pendingSession.loadCast();
        } else {
          final newer = PlayerNativeSession(
            invoke: (_, _) async => true,
            local: (action, _) async => writes.add('new:$action'),
            media: () => {},
            isPlaying: () => false,
            isCurrent: () => true,
          )..claim();
          addTearDown(newer.release);
        }
        pause.complete();
        await load;
        await newerLoad;
        expect(writes, cancellation == 'stop' ? ['pause', 'stop'] : ['pause']);
        expect(pendingSession.casting, false);
      },
    );
  }
  for (final initiallyPlaying in [true, false]) {
    for (final throws in [false, true]) {
      test(
        'Cast ${throws ? 'throw' : 'rejection'} preserves newer ${initiallyPlaying ? 'pause' : 'play'} intent',
        () async {
          final response = Completer<bool>();
          final writes = <String>[];
          final failures = <String>[];
          final pendingSession = PlayerNativeSession(
            castRequested: true,
            invoke: (_, _) => response.future,
            local: (action, _) async => writes.add(action),
            media: () => {'url': 'https://media.test/current.mp4'},
            isPlaying: () => initiallyPlaying,
            isCurrent: () => true,
            failure: failures.add,
          )..claim();
          addTearDown(pendingSession.release);
          final load = pendingSession.handle(
            const MethodCall('castChanged', {'connected': true}),
          );
          await Future<void>.delayed(Duration.zero);
          final intent = initiallyPlaying ? 'pause' : 'play';
          await pendingSession.command(intent);
          if (throws) {
            response.completeError(StateError('native load failed'));
          } else {
            response.complete(false);
          }
          await load;
          expect(writes, ['pause', intent, intent]);
          expect(pendingSession.casting, false);
          expect(failures, hasLength(1));
        },
      );
    }
  }
  for (final cancellation in ['stop', 'release', 'new owner', 'new load']) {
    test(
      'stale throwing Cast load cannot overwrite state after $cancellation',
      () async {
        final response = Completer<bool>();
        final writes = <String>[];
        final failures = <String>[];
        var loads = 0;
        final pendingSession = PlayerNativeSession(
          castRequested: true,
          invoke: (method, _) async {
            if (method == 'castLoad' && ++loads == 1) return response.future;
            return true;
          },
          local: (action, _) async => writes.add(action),
          media: () => {'url': 'https://media.test/current.mp4'},
          isPlaying: () => true,
          isCurrent: () => true,
          failure: failures.add,
        )..claim();
        addTearDown(pendingSession.release);
        final load = pendingSession.handle(
          const MethodCall('castChanged', {'connected': true}),
        );
        await Future<void>.delayed(Duration.zero);
        Future<void>? newerLoad;
        if (cancellation == 'stop') {
          await pendingSession.command('stop');
        } else if (cancellation == 'release') {
          pendingSession.release();
        } else if (cancellation == 'new load') {
          newerLoad = pendingSession.loadCast();
        } else {
          final newer = PlayerNativeSession(
            invoke: (_, _) async => true,
            local: (action, _) async => writes.add('new:$action'),
            media: () => {},
            isPlaying: () => false,
            isCurrent: () => true,
          )..claim();
          addTearDown(newer.release);
        }
        response.completeError(StateError('malicious late native failure'));
        await load;
        await newerLoad;
        expect(failures, isEmpty);
        expect(
          writes,
          cancellation == 'stop'
              ? ['pause', 'stop']
              : cancellation == 'new load'
              ? ['pause', 'pause']
              : ['pause'],
        );
        expect(pendingSession.casting, cancellation == 'new load');
      },
    );
  }
  test(
    'notification stop ends background session without automatic restart',
    () async {
      await session.background(
        enabled: true,
        playing: true,
        position: Duration.zero,
        duration: Duration.zero,
      );
      await session.command('stop');
      expect(native.last.method, 'backgroundPlaybackStop');
      final count = native.length;
      await session.background(
        enabled: true,
        playing: false,
        position: Duration.zero,
        duration: Duration.zero,
      );
      expect(native.length, count);
      await session.command('play');
      await session.background(
        enabled: true,
        playing: true,
        position: Duration.zero,
        duration: Duration.zero,
      );
      expect(native.last.method, 'backgroundPlayback');
    },
  );
  test(
    'background bridge starts only by opt-in and updates exact metadata',
    () async {
      await session.background(
        enabled: false,
        playing: true,
        position: Duration.zero,
        duration: Duration.zero,
      );
      expect(native, isEmpty);
      await session.background(
        enabled: true,
        playing: true,
        position: const Duration(seconds: 12),
        duration: const Duration(seconds: 60),
      );
      expect(native.last.method, 'backgroundPlayback');
      expect(native.last.arguments, {
        'enabled': true,
        'title': 'Episode 2',
        'playing': true,
        'positionMs': 12000,
        'durationMs': 60000,
      });
      await session.background(
        enabled: true,
        playing: false,
        position: const Duration(seconds: 15),
        duration: const Duration(seconds: 60),
      );
      expect(native.last.method, 'backgroundPlaybackUpdate');
      await session.background(
        enabled: false,
        playing: false,
        position: Duration.zero,
        duration: Duration.zero,
      );
      expect(native.last.method, 'backgroundPlaybackStop');
    },
  );
}
