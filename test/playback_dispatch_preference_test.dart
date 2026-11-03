import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelbox/media/media_helpers.dart';

void main() {
  for (final autoplay in [true, false]) {
    test(
      'engine open dispatch uses autoplay=$autoplay for remote and offline media',
      () async {
        for (final uri in ['https://example.test/a.mp4', '/offline/a.mp4']) {
          final calls = <({Media media, bool play})>[];
          await dispatchMediaOpen(
            open: (media, {play = true}) async =>
                calls.add((media: media, play: play)),
            uri: uri,
            start: const Duration(seconds: 20),
            autoplay: autoplay,
          );
          expect(calls.single.play, autoplay);
          expect(calls.single.media.uri, uri);
          expect(calls.single.media.start, const Duration(seconds: 20));
        }
      },
    );
  }
}
