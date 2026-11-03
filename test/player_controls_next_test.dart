import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_helpers.dart';
import 'package:reelbox/media/player_page.dart';

void main() {
  test(
    'resume rewinds but completed progress resets without negative positions',
    () {
      expect(
        resumePosition(
          position: const Duration(seconds: 60),
          duration: const Duration(seconds: 600),
          rewindSeconds: 5,
        ),
        const Duration(seconds: 55),
      );
      expect(
        resumePosition(
          position: const Duration(seconds: 6),
          duration: const Duration(seconds: 600),
          rewindSeconds: 120,
        ),
        Duration.zero,
      );
      expect(
        resumePosition(
          position: const Duration(seconds: 590),
          duration: const Duration(seconds: 600),
          rewindSeconds: 5,
        ),
        Duration.zero,
      );
    },
  );
  test(
    'grouped subtitle variants inherit language and reject unsafe sources',
    () {
      final groups = subtitleGroups([
        {
          'language': 'Persian',
          'subtitles': [
            {'title': 'WEB-DL', 'url': 'https://media.test/fa.srt'},
            {'name': 'BluRay', 'link': 'https://media.test/fa2.srt'},
            {'url': 'javascript:bad'},
          ],
        },
        {
          'language': {'name': 'English'},
          'title': 'SDH',
          'url': 'https://media.test/en.vtt',
        },
      ]);
      expect(groups.keys, ['Persian', 'English']);
      expect(groups['Persian']!.map((e) => e.label), ['WEB-DL', 'BluRay']);
      expect(groups['English']!.single.url, 'https://media.test/en.vtt');
    },
  );
  testWidgets(
    'keyboard media shortcuts dispatch commands; locked rejects input',
    (tester) async {
      final actions = <String>[];
      Future<void> mount(bool locked) => tester.pumpWidget(
        MaterialApp(
          home: PlayerInteraction(
            locked: locked,
            controlsVisible: true,
            onAction: actions.add,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await mount(false);
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.keyS,
      ]) {
        await tester.sendKeyEvent(key);
      }
      expect(actions, [
        'toggle',
        'mute',
        'fullscreen',
        'back',
        'next',
        'subtitles',
      ]);
      await mount(true);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(actions.length, 6);
    },
  );
  testWidgets('double click requests fullscreen rather than changing fit', (
    tester,
  ) async {
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerInteraction(
          locked: false,
          controlsVisible: true,
          onAction: actions.add,
          child: PlayerSurfaceGestures(locked: false, onAction: actions.add),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(actions, contains('fullscreen'));
    expect(actions, isNot(contains('fit')));
  });
}
