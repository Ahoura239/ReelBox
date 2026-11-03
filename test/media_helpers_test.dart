import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:reelbox/media/download_service.dart';

import 'dart:convert';

import 'package:reelbox/media/media_helpers.dart';

void main() {
  test('sources retain public variants, remove trailers and unusable URLs', () {
    const a = MediaSource(
      id: 1,
      quality: '720p',
      url: 'http://media.example/a.mp4?token=x',
    );
    expect(
      playableSources([
        a,
        a,
        const MediaSource(url: 'javascript:alert(1)'),
        const MediaSource(quality: 'trailer', url: 'https://example.com/t.mp4'),
      ]),
      [a],
    );
  });
  test(
    'source preference selects exact quality without inventing an access gate',
    () {
      const sd = MediaSource(quality: '480p', url: 'https://example.com/s.mp4');
      const hd = MediaSource(
        quality: '1080p',
        url: 'https://example.com/h.mp4',
      );
      expect(selectSource([sd, hd], preferredQuality: '1080p'), hd);
      expect(selectSource([sd, hd], preferredQuality: 'unavailable'), sd);
      expect(selectSource([]), isNull);
    },
  );
  test(
    'resume ignores completed and invalid positions and keeps exact identity',
    () {
      expect(
        resumePosition(
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 20),
        ),
        const Duration(seconds: 30),
      );
      expect(
        resumePosition(
          position: const Duration(seconds: -5),
          duration: const Duration(minutes: 20),
        ),
        Duration.zero,
      );
      expect(
        resumePosition(
          position: const Duration(seconds: 1190),
          duration: const Duration(minutes: 20),
        ),
        Duration.zero,
      );
      expect(watchKey(7, null), '7:movie');
      expect(watchKey(7, 12), '7:12');
    },
  );
  test('next episode stays ordered and does not silently skip an unavailable episode', () {
    const episodes = [
      EpisodeRecord(id: 1),
      EpisodeRecord(id: 2),
      EpisodeRecord(id: 3),
    ];
    expect(nextEpisode(episodes, 1)?.id, 2);
    expect(nextEpisode(episodes, 3), isNull);
    expect(nextEpisode(episodes, 99), isNull);
  });
  test(
    'download names are private-path safe and stream manifests rejected',
    () {
      expect(
        downloadFilename(
          title: '../A/B: Film',
          identity: '7_8',
          url: 'https://example.com/movie.mkv?secret=a',
        ),
        'A_B_ Film_7_8.mkv',
      );
      expect(
        downloadUnsupportedReason(
          const MediaSource(url: 'https://example.com/master.m3u8'),
        ),
        isNotNull,
      );
      expect(
        downloadUnsupportedReason(
          const MediaSource(url: 'https://example.com/a.mp4'),
        ),
        isNull,
      );
    },
  );
  test('download metadata survives native task serialization with bounded progress', () {
    final task = DownloadTask(
      taskId: 'a',
      url: 'http://example.com/video.mp4',
      filename: 'video.mp4',
      metaData: jsonEncode({
        'title': 'Movie',
        'titleId': 17,
        'quality': '1080p',
        'episodeId': 8,
        'episodeTitle': 'Ep 8',
        'posterImage': 'poster',
      }),
    );
    final restored = DownloadTask.fromJson(task.toJson());
    final entry = DownloadEntry.fromTask(
      restored,
      taskStatus: TaskStatus.paused,
      progress: -5,
      totalBytes: 1000,
    );
    expect(entry.title, 'Movie');
    expect(entry.titleId, 17);
    expect(entry.episodeId, 8);
    expect(entry.progress, 0);
    expect(entry.canResume, isTrue);
    expect(entry.isComplete, isFalse);
    expect(
      DownloadEntry.fromTask(task, taskStatus: TaskStatus.complete).progress,
      1,
    );
    expect(
      DownloadEntry.fromTask(
        task,
        taskStatus: TaskStatus.failed,
        progress: 1.7,
      ).progress,
      1,
    );
    expect(
      DownloadEntry.fromTask(task, taskStatus: TaskStatus.running).canPause,
      isTrue,
    );
  });
}
