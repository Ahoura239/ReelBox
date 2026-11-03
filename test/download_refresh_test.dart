import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/download_service.dart';

void main() {
  test(
    'download refresh awaits durable records rather than repainting old state',
    () async {
      final pending = Completer<List<TaskRecord>>();
      var calls = 0;
      var finished = false;
      final result = readDownloadEntries(() {
        calls++;
        return pending.future;
      });
      result.then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(finished, isFalse);
      final task = DownloadTask(
        taskId: 'reloaded',
        url: 'https://example.test/a.mp4',
        baseDirectory: BaseDirectory.root,
        directory: '/reelbox-offline',
        filename: 'a.mp4',
      );
      pending.complete([TaskRecord(task, TaskStatus.paused, .4, 1000)]);
      final entries = await result;
      expect(entries.single.id, 'reloaded');
      expect(entries.single.receivedBytes, 400);
      expect(entries.single.canResume, isTrue);
      expect(entries.single.path, '/reelbox-offline/a.mp4');
    },
  );
}
