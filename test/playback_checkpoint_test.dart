import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_helpers.dart';

void main() {
  test('opening a player cannot overwrite an existing resume checkpoint', () {
    final playback = PlaybackCheckpoint();
    const savedPosition = Duration(minutes: 17);
    var storedPosition = savedPosition;
    void persist() {
      if (playback.canPersist) storedPosition = playback.position;
    }

    persist();
    playback.beginOpen();
    persist();
    expect(storedPosition, savedPosition);
    expect(playback.canPersist, isFalse);
    // Failed opens, duration discovery and a zero position are not watched time.
    playback.duration = const Duration(hours: 2);
    playback.position = Duration.zero;
    persist();
    expect(storedPosition, savedPosition);
    playback.didOpen();
    persist();
    expect(storedPosition, savedPosition);
    playback.position = const Duration(minutes: 18);
    persist();
    expect(storedPosition, const Duration(minutes: 18));
  });
  test(
    'source switches do not attribute previous progress to the new source',
    () {
      final playback = PlaybackCheckpoint();
      playback.beginOpen();
      playback.didOpen();
      playback.position = const Duration(minutes: 3);
      expect(playback.canPersist, isTrue);
      playback.beginOpen();
      expect(playback.position, Duration.zero);
      expect(playback.canPersist, isFalse);
      playback.position = const Duration(seconds: 40);
      expect(playback.canPersist, isFalse);
      playback.didOpen();
      expect(playback.canPersist, isTrue);
    },
  );
}
