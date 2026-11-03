import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_helpers.dart';

void main() {
  for (final disposeFirst in [true, false]) {
    test(
      'old player teardown cannot overwrite new owner (dispose first=$disposeFirst)',
      () async {
        final old = PlaybackLifecycle();
        final current = PlaybackLifecycle();
        final pending = Completer<void>();
        final writes = <String>[];
        final oldSetup = old.setup([
          () async {
            writes.add('old-active');
            await pending.future;
          },
        ]);
        await Future<void>.delayed(Duration.zero);
        late Future<void> teardown;
        late Future<bool> newSetup;
        Future<void> restoreOld() async {
          writes.add('old-restore');
        }

        Future<void> setupNew() async {
          writes.add('new-active');
        }

        if (disposeFirst) {
          teardown = old.dispose(restoreOld);
          newSetup = current.setup([setupNew]);
        } else {
          newSetup = current.setup([setupNew]);
          teardown = old.dispose(restoreOld);
        }
        await Future<void>.delayed(Duration.zero);
        pending.complete();
        expect(await oldSetup, isFalse);
        expect(await newSetup, isTrue);
        await teardown;
        expect(writes.last, 'new-active');
        await current.dispose(() async {
          writes.add('new-restore');
        });
        expect(writes.last, 'new-restore');
      },
    );
  }
}
