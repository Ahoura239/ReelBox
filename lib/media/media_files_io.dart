import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';

import 'segmented_download.dart';
import '../data/content_policy.dart';

import 'dart:convert';

Future<bool> exists(String path) async =>
    await File(path).exists() && await File(path).length() > 0;
Future<int> size(String path) => File(path).length();
Future<void> delete(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

const _segmentGroup = 'reelbox.offline.resources';
Future<SegmentedDownload>? _packageEngine;
final _nativeTasks = <String, Set<String>>{};
final _activePackages = <String>{};
Future<SegmentedDownload> _engine() => _packageEngine ??= () async {
  final support = await getApplicationSupportDirectory();
  return SegmentedDownload(
    root: Directory('${support.path}/offline_packages'),
    transfer: _nativeTransfer,
    cancelTransfers: _cancelTransfers,
  );
}();

Future<void> _cancelTransfers(String id) async {
  final ids = _nativeTasks[id]?.toList() ?? <String>[];
  if (ids.isNotEmpty && !await FileDownloader().cancelTasksWithIds(ids)) {
    throw StateError('Android could not cancel an offline resource task.');
  }
}

Future<void> _nativeTransfer(
  OfflinePackage p,
  OfflineResource r,
  String destination,
) async {
  final original = Task.createFromJson(
    Map<String, dynamic>.from(p.metadata['task'] as Map),
  );
  final metadata = original.metaData;
  final meta = Map<String, dynamic>.from(jsonDecode(metadata) as Map);
  if (!ContentPolicy.allowsTitleJson({
        'title': meta['title'],
        'type': meta['titleKind'],
      }) ||
      !ContentPolicy.allowsText(meta['episodeTitle'] as String? ?? '') ||
      !ContentPolicy.allowsUrl(r.url)) {
    throw UnsupportedError(
      'Excluded offline metadata cannot start a native job.',
    );
  }
  final id = '${p.id}_${r.filename}_${DateTime.now().microsecondsSinceEpoch}';
  final enabled = (p.metadata['notifications'] as bool?) ?? false;
  final task = DownloadTask(
    taskId: id,
    url: r.url,
    headers: {
      'Accept-Encoding': 'identity',
      if (r.offset != null)
        'Range': 'bytes=${r.offset}-${r.offset! + r.length! - 1}',
    },
    // Per-run names keep orphan OS writers away from the resumed destination.
    filename: '${File(destination).uri.pathSegments.last}.$id.part',
    directory: File(destination).parent.path,
    baseDirectory: BaseDirectory.root,
    group: _segmentGroup,
    requiresWiFi: original.requiresWiFi,
    retries: 2,
    allowPause: false,
    updates: Updates.statusAndProgress,
    displayName: original.displayName,
    metaData: metadata,
    notificationConfig: enabled
        ? TaskNotificationConfig(
            running: const TaskNotification(
              'Reelbox • saving offline resource',
              '{displayName}\n{progress}',
            ),
            error: const TaskNotification(
              'Reelbox • offline resource failed',
              '{displayName}',
            ),
            progressBar: true,
            tapOpensFile: false,
          )
        : null,
  );
  (_nativeTasks[p.id] ??= <String>{}).add(id);
  try {
    final update = await FileDownloader().download(task);
    if (update.status != TaskStatus.complete) {
      throw StateError('Native resource download ${update.status.name}.');
    }
    final code = update.responseStatusCode;
    if (r.offset != null) {
      final range = update.responseHeaders?['content-range'] ?? '';
      if (code != 206 ||
          !RegExp('^bytes ${r.offset}-${r.offset! + r.length! - 1}/[0-9]+\$')
              .hasMatch(range)) {
        throw const FormatException(
          'Server did not honor the resource byte range.',
        );
      }
    } else if (code != 200) {
      throw StateError('Native resource HTTP $code.');
    }
    final expected = int.tryParse(
      update.responseHeaders?['content-length'] ?? '',
    );
    final downloaded = File(await task.filePath());
    if (expected != null && expected != await downloaded.length()) {
      throw const FormatException('Truncated native resource.');
    }
    await downloaded.rename(destination);
  } finally {
    _nativeTasks[p.id]?.remove(id);
    await FileDownloader().database.deleteRecordWithId(id);
  }
}

Map<String, dynamic> _snapshot(OfflinePackage p) => {
  ...p.toJson(),
  'path': p.path,
  'directory': p.directory,
  'receivedBytes': p.receivedBytes,
  'progress': p.progress,
};
Future<List<Map<String, dynamic>>> recoverPackages() async {
  // Interrupted child jobs must not race a newly resumed writer to the same .part.
  final downloader = FileDownloader();
  final tasks = await downloader.allTasks(group: _segmentGroup);
  final orphans = tasks
      .where((t) => !_nativeTasks.values.any((ids) => ids.contains(t.taskId)))
      .toList();
  if (orphans.isNotEmpty &&
      !await downloader.cancelTasksWithIds(
        orphans.map((t) => t.taskId).toList(),
      )) {
    throw StateError(
      'Cannot recover while Android still owns an old resource job.',
    );
  }
  return (await (await _engine()).recover()).map(_snapshot).toList();
}

Future<Map<String, dynamic>> preparePackage({
  required String id,
  required String url,
  required String type,
  required Map<String, dynamic> metadata,
  required int parallel,
}) async {
  final engine = await _engine();
  engine.parallel = parallel.clamp(1, 8);
  return _snapshot(
    await engine.prepare(id: id, url: url, type: type, metadata: metadata),
  );
}

Future<void> runPackage(
  String id,
  void Function(Map<String, dynamic>) onProgress,
) async {
  if (!_activePackages.add(id)) {
    throw StateError('Offline package is already active.');
  }
  try {
    await (await _engine()).run(
      id,
      onProgress: (p) => onProgress(_snapshot(p)),
    );
  } finally {
    _activePackages.remove(id);
  }
}

Future<void> pausePackage(String id, {bool cancel = false}) async =>
    (await _engine()).stop(id, cancel: cancel);
Future<void> deletePackage(String id) async => (await _engine()).delete(id);
Future<String> exportPackage(String id) async => (await _engine()).export(id);
Future<bool> validatePackage(String id) async => (await _engine()).validate(id);
Future<Map<String, dynamic>> loadPackage(String id) async =>
    _snapshot(await (await _engine()).load(id));
