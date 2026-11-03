import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
// Exercise the pinned plugin's resolver without native/network initialization.
// ignore: implementation_imports
import 'package:background_downloader/src/base_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/media/download_service.dart';

void main() {
  for (final enabled in [true, false]) {
    test(
      'restart resume preserves original notifications=$enabled before dispatch',
      () async {
        final service = DownloadService.instance;
        service.configureNotifications(enabled);
        final original = DownloadTask(
          url: 'https://example.test/a.mp4',
          group: DownloadService.group,
          notificationConfig: service.notificationConfigForNewTask,
          metaData: downloadMetadata(
            title: const TitleRecord(id: 7, title: 'Fixture'),
            source: const MediaSource(url: 'https://example.test/a.mp4'),
            notifications: enabled,
          ),
        );
        final recovered = DownloadTask.fromJson(
          jsonDecode(jsonEncode(original.toJson())),
        );
        expect(recovered.notificationConfig, isNull);
        service.configureNotifications(!enabled);
        final events = <String>[];
        final registry = <TaskNotificationConfig>{};
        final ok = await resumeDownloadTask(
          DownloadEntry.fromTask(recovered),
          configure: (task, config) {
            events.add('configure');
            registry.add(
              TaskNotificationConfig(
                taskOrGroup: task,
                running: config.running,
                complete: config.complete,
                error: config.error,
                paused: config.paused,
                progressBar: config.progressBar,
                tapOpensFile: config.tapOpensFile,
              ),
            );
          },
          resume: (task) async {
            events.add('resume');
            final registered =
                BaseDownloader.notificationConfigForTaskUsingConfigSet(
                  task,
                  registry,
                );
            expect(registered?.running != null, enabled);
            expect(registered?.complete != null, enabled);
            expect(registered?.error != null, enabled);
            expect(registered?.paused != null, enabled);
            return true;
          },
        );
        expect(ok, isTrue);
        expect(events, enabled ? ['configure', 'resume'] : ['resume']);
        expect(
          jsonDecode(recovered.metaData)['downloadNotifications'],
          enabled,
        );
      },
    );
  }
}
