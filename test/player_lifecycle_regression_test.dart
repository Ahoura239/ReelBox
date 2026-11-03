import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_helpers.dart';

void main() {
  for (final pendingStep in [0, 1, 2]) {
    test(
      'dispose during setup step $pendingStep cancels later writes; restore is last',
      () async {
        final lifecycle = PlaybackLifecycle();
        final entered = Completer<void>();
        final release = Completer<void>();
        final events = <String>[];
        final setup = lifecycle.setup([
          for (var i = 0; i < 3; i++)
            () async {
              if (i == pendingStep) {
                entered.complete();
                await release.future;
              }
              events.add('setup:$i');
            },
        ]);
        await entered.future;
        final restore = lifecycle.dispose(() async => events.add('restore'));
        release.complete();
        expect(await setup, isFalse);
        await restore;
        expect(events, [
          for (var i = 0; i <= pendingStep; i++) 'setup:$i',
          'restore',
        ]);
      },
    );
  }
  test('dispose during save prevents any player open dispatch', () async {
    final lifecycle = PlaybackLifecycle();
    final save = Completer<void>();
    var opens = 0;
    final opening = lifecycle.open(
      save: () => save.future,
      dispatch: (_) async {
        opens++;
      },
    );
    await lifecycle.dispose(() async {});
    save.complete();
    expect(await opening, isFalse);
    expect(opens, 0);
  });
  test('newer open wins even when an older save completes last', () async {
    final lifecycle = PlaybackLifecycle();
    final save = Completer<void>();
    final opened = <String>[];
    final older = lifecycle.open(
      save: () => save.future,
      dispatch: (_) async => opened.add('old'),
    );
    expect(
      await lifecycle.open(
        save: () async {},
        dispatch: (_) async => opened.add('new'),
      ),
      isTrue,
    );
    save.complete();
    expect(await older, isFalse);
    expect(opened, ['new']);
  });
  test('disposed lifecycle rejects new setup and open work', () async {
    final lifecycle = PlaybackLifecycle();
    await lifecycle.dispose(() async {});
    var calls = 0;
    expect(
      await lifecycle.setup([
        () async {
          calls++;
        },
      ]),
      isFalse,
    );
    expect(
      await lifecycle.open(
        save: () async {
          calls++;
        },
        dispatch: (_) async {
          calls++;
        },
      ),
      isFalse,
    );
    expect(calls, 0);
  });
}
