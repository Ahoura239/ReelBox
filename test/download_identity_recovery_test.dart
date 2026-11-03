import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/media/download_service.dart';
import 'package:reelbox/state/app_state.dart';

void main() {
  for (final kind in ['channel', 'movie', 'serie', 'series']) {
    test(
      'offline and retry reconstruction preserve $kind after disk round trip',
      () {
        final title = TitleRecord(id: 42, title: 'Fixture', type: kind);
        final original = DownloadTask(
          url: 'https://example.test/a.mp4',
          metaData: downloadMetadata(
            title: title,
            source: const MediaSource(url: 'https://example.test/a.mp4'),
            notifications: false,
          ),
        );
        final recovered = DownloadTask.fromJson(
          jsonDecode(jsonEncode(original.toJson())),
        );
        final restored = DownloadEntry.fromTask(recovered).restoredTitle;
        expect(restored.type, kind);
        expect(restored.libraryKey, title.libraryKey);
      },
    );
  }
  test(
    'legacy records retain the movie/episode fallback without guessing channel',
    () {
      for (final episodeId in [null, 9]) {
        final task = DownloadTask(
          url: 'https://example.test/a.mp4',
          metaData: jsonEncode({'titleId': 42, 'episodeId': episodeId}),
        );
        final title = DownloadEntry.fromTask(task).restoredTitle;
        expect(title.type, episodeId == null ? 'movie' : 'serie');
        expect(title.libraryKey, 'poster:42');
      }
    },
  );
}
