import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Cast prepares an owned resource only after an explicit request and revokes on disconnect', () async {
    final prepared = Completer<Map<String, dynamic>>();
    final events = <String>[];
    final payloads = <Map<String, dynamic>>[];
    var preparations = 0, revocations = 0;
    final session = PlayerNativeSession(
      invoke: (method, args) async {
        events.add(method);
        if (method == 'castLoad') payloads.add(args!);
        return true;
      },
      local: (action, _) async => events.add(action),
      media: () => {'url': '/selected/offline.mp4', 'title': 'Film'},
      prepareMedia: () {
        preparations++;
        return prepared.future;
      },
      revokeMedia: () async {
        revocations++;
      },
      isPlaying: () => true,
      isCurrent: () => true,
    )..claim();
    addTearDown(session.release);
    await session.handle(const MethodCall('castChanged', {'connected': true}));
    expect(events, isEmpty);
    expect(preparations, 0);
    expect(await session.picker(), true);
    final load = session.handle(
      const MethodCall('castChanged', {'connected': true}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(preparations, 1);
    expect(events, ['castShowPicker']); // No premature pause or raw file URL.
    prepared.complete({
      'url': 'http://127.0.0.1:1234/synthetic/media.mp4',
      'title': 'Film',
    });
    await load;
    expect(events, ['castShowPicker', 'pause', 'castLoad']);
    expect(payloads.single['url'], startsWith('http://'));
    expect(session.casting, true);
    await session.handle(const MethodCall('castChanged', {'connected': false}));
    expect(revocations, 1);
    expect(session.casting, false);
  });

  test('a newer media request supersedes pending preparation without casting stale media', () async {
    final first = Completer<Map<String, dynamic>>();
    final loaded = <String>[];
    var preparations = 0;
    final session = PlayerNativeSession(
      castRequested: true,
      invoke: (method, args) async {
        if (method == 'castLoad') loaded.add(args!['url'] as String);
        return true;
      },
      local: (_, _) async {},
      media: () => {},
      prepareMedia: () async {
        if (++preparations == 1) return first.future;
        return {'url': 'https://media.test/new.mp4'};
      },
      revokeMedia: () async {},
      isPlaying: () => true,
      isCurrent: () => true,
    )..claim();
    addTearDown(session.release);
    final old = session.handle(
      const MethodCall('castChanged', {'connected': true}),
    );
    await Future<void>.delayed(Duration.zero);
    final newer = session.loadCast();
    first.complete({'url': 'https://media.test/old.mp4'});
    await Future.wait([old, newer]);
    expect(preparations, 2);
    expect(loaded, ['https://media.test/new.mp4']);
  });

  test(
    'remote stop revokes sharing and connected polls do not restart it',
    () async {
      var live = false;
      final native = <String>[];
      final session = PlayerNativeSession(
        castRequested: true,
        invoke: (method, _) async {
          native.add(method);
          return true;
        },
        local: (_, _) async {},
        media: () => {},
        prepareMedia: () async {
          live = true;
          return {'url': 'https://media.test/film.mp4'};
        },
        revokeMedia: () async {
          live = false;
        },
        isPlaying: () => true,
        isCurrent: () => true,
      )..claim();
      addTearDown(session.release);
      await session.handle(
        const MethodCall('castChanged', {'connected': true}),
      );
      expect(live, true);
      await session.command('stop');
      expect(live, false);
      expect(session.casting, false);
      await session.handle(
        const MethodCall('castChanged', {'connected': true}),
      );
      expect(native.where((method) => method == 'castLoad'), hasLength(1));
    },
  );
}
