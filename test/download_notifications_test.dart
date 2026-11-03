import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/download_service.dart';

void main() {
  test('new downloads have no stale notification templates after opt out', () {
    final service = DownloadService.instance;
    service.configureNotifications(true);
    final enabledTask = DownloadTask(
      url: 'https://example.test/a.mp4',
      group: DownloadService.group,
      notificationConfig: service.notificationConfigForNewTask,
    );
    expect(enabledTask.notificationConfig?.complete, isNotNull);
    service.configureNotifications(false);
    final disabledTask = DownloadTask(
      url: 'https://example.test/b.mp4',
      group: DownloadService.group,
      notificationConfig: service.notificationConfigForNewTask,
    );
    expect(disabledTask.notificationConfig, isNull);
    // Changing the preference does not lie about altering an active OS job.
    expect(enabledTask.notificationConfig?.running, isNotNull);
  });
}
