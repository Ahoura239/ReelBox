import 'dart:convert';
import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/content_policy.dart';
import 'media_platform.dart';
import '../state/app_state.dart';
import 'media_helpers.dart';
import 'media_files_stub.dart'
    if (dart.library.io) 'media_files_io.dart'
    as files;

/// A snapshot of the persistent native task, not an optimistic success flag.
class DownloadEntry {
  final Task task;
  final String id,
      title,
      quality,
      filename,
      path,
      url,
      status,
      error,
      episodeTitle,
      posterImage;
  final int titleId;
  final String titleKind;
  final bool? downloadNotifications;
  final int? episodeId;
  final double progress, speed;
  final int receivedBytes, totalBytes;
  final TaskStatus taskStatus;

  DownloadEntry._({
    required this.task,
    required this.id,
    required this.title,
    required this.quality,
    required this.filename,
    required this.path,
    required this.url,
    required this.status,
    required this.error,
    required this.episodeTitle,
    required this.posterImage,
    required this.titleId,
    required this.titleKind,
    required this.downloadNotifications,
    required this.episodeId,
    required this.progress,
    required this.speed,
    required this.receivedBytes,
    required this.totalBytes,
    required this.taskStatus,
  });

  factory DownloadEntry.fromTask(
    Task task, {
    TaskStatus taskStatus = TaskStatus.enqueued,
    double progress = 0,
    int totalBytes = 0,
    int? receivedBytes,
    double speed = 0,
    String path = '',
    String error = '',
  }) {
    Map<String, dynamic> meta = {};
    try {
      final decoded = jsonDecode(task.metaData);
      if (decoded is Map) meta = Map<String, dynamic>.from(decoded);
    } catch (_) {
      /* Tasks from older installs can lack metadata. */
    }
    final fraction = taskStatus == TaskStatus.complete
        ? 1.0
        : progress.isFinite
        ? progress.clamp(0.0, 1.0)
        : 0.0;
    final size = totalBytes > 0 ? totalBytes : 0;
    return DownloadEntry._(
      task: task,
      id: task.taskId,
      title: meta['title'] as String? ?? task.displayName,
      quality: meta['quality'] as String? ?? '',
      filename: task.filename,
      path: path,
      url: task.url,
      status: taskStatus.name,
      error: error,
      episodeTitle: meta['episodeTitle'] as String? ?? '',
      posterImage: meta['posterImage'] as String? ?? '',
      titleId: meta['titleId'] as int? ?? 0,
      titleKind: (meta['titleKind'] as String?)?.isNotEmpty == true
          ? meta['titleKind'] as String
          : meta['episodeId'] == null
          ? 'movie'
          : 'serie',
      downloadNotifications:
          meta['downloadNotifications'] as bool? ??
          (task.notificationConfig != null ? true : null),
      episodeId: meta['episodeId'] as int?,
      progress: fraction,
      speed: speed.isFinite && speed > 0 ? speed : 0,
      receivedBytes: receivedBytes ?? (fraction * size).round(),
      totalBytes: size,
      taskStatus: taskStatus,
    );
  }

  TitleRecord get restoredTitle => TitleRecord(
    id: titleId,
    title: title,
    image: posterImage,
    type: titleKind,
  );

  String get sourceType {
    try {
      return (jsonDecode(task.metaData) as Map)['sourceType'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  bool get isSegmented => task.group == DownloadService.packageGroup;
  bool get visible =>
      ContentPolicy.allowsTitleJson(restoredTitle.toJson()) &&
      ContentPolicy.allowsText(episodeTitle) &&
      ContentPolicy.allowsUrl(url);
  bool get isComplete => taskStatus == TaskStatus.complete;
  bool get canPause => taskStatus == TaskStatus.running;
  bool get canResume => taskStatus == TaskStatus.paused;
  bool get isActive => {
    TaskStatus.running,
    TaskStatus.enqueued,
    TaskStatus.waitingToRetry,
  }.contains(taskStatus);
}

/// Resolve a fresh durable snapshot, awaiting both storage and file paths.
Future<List<DownloadEntry>> readDownloadEntries(
  Future<List<TaskRecord>> Function() load,
) async {
  final records = await load();
  return Future.wait(
    records.map(
      (record) async => DownloadEntry.fromTask(
        record.task,
        taskStatus: record.status,
        progress: record.progress,
        totalBytes: record.expectedFileSize,
        path: await record.task.filePath(),
        error: record.exception?.description ?? '',
      ),
    ),
  );
}

TaskNotificationConfig? downloadNotificationConfig(bool enabled) => enabled
    ? TaskNotificationConfig(
        running: const TaskNotification(
          'Reelbox • downloading',
          '{displayName}\n{progress} • {networkSpeed}',
        ),
        complete: const TaskNotification(
          'Reelbox • downloaded',
          '{displayName}',
        ),
        error: const TaskNotification(
          'Reelbox • download failed',
          '{displayName}',
        ),
        paused: const TaskNotification('Reelbox • paused', '{displayName}'),
        progressBar: true,
        tapOpensFile: true,
      )
    : null;

// Shared by enqueue and restart recovery tests; metadata is the durable policy.
String downloadMetadata({
  required TitleRecord title,
  required MediaSource source,
  required bool notifications,
  EpisodeRecord? episode,
}) => jsonEncode({
  'title': title.title,
  'titleId': title.id,
  'titleKind': title.type,
  'downloadNotifications': notifications,
  'quality': source.quality,
  'sourceType': source.type,
  'episodeId': episode?.id,
  'episodeTitle': episode?.title ?? '',
  'posterImage': title.image,
});

Future<bool> resumeDownloadTask(
  DownloadEntry entry, {
  required void Function(Task task, TaskNotificationConfig config) configure,
  required Future<bool> Function(DownloadTask task) resume,
}) async {
  if (entry.task is! DownloadTask) return false;
  // Task.notificationConfig is deliberately omitted by plugin serialization.
  // Unknown legacy policy stays silent rather than adopting today's setting.
  final config = downloadNotificationConfig(
    entry.downloadNotifications ?? false,
  );
  // The pinned plugin rejects an all-null notification configuration. Off-policy
  // tasks have no templates registered (and this service has no group/default).
  if (config != null) configure(entry.task, config);
  return resume(entry.task as DownloadTask);
}

DownloadTask createDirectDownloadTask({
  required String id,
  required TitleRecord title,
  required MediaSource source,
  required AppSettings preferences,
  EpisodeRecord? episode,
}) {
  final task = DownloadTask(
    taskId: id,
    url: source.url,
    filename: downloadFilename(
      title: episode == null ? title.title : '${title.title} ${episode.title}',
      identity: id,
      url: source.url,
    ),
    baseDirectory: BaseDirectory.applicationSupport,
    directory: 'offline',
    group: DownloadService.group,
    notificationConfig: downloadNotificationConfig(
      preferences.downloadNotifications,
    ),
    updates: Updates.statusAndProgress,
    requiresWiFi: preferences.wifiOnlyDownloads,
    allowPause: true,
    retries: 2,
    displayName: episode == null
        ? title.title
        : '${title.title} • ${episode.title}',
    metaData: downloadMetadata(
      title: title,
      source: source,
      episode: episode,
      notifications: preferences.downloadNotifications,
    ),
  );

  if (preferences.parallelDownloads <= 1) return task;
  // 9.6.5 exposes real HTTP range chunk tasks, not concurrent whole-file copies.
  return ParallelDownloadTask(
    taskId: task.taskId,
    url: task.url,
    filename: task.filename,
    chunks: preferences.parallelDownloads.clamp(1, 8),
    baseDirectory: task.baseDirectory,
    directory: task.directory,
    group: task.group,
    notificationConfig: task.notificationConfig,
    updates: task.updates,
    requiresWiFi: task.requiresWiFi,
    allowPause: true,
    retries: task.retries,
    displayName: task.displayName,
    metaData: task.metaData,
  );
}

Future<void> retireExcludedDownload(
  TaskRecord record, {
  required Future<bool> Function(String) cancel,
}) async {
  final entry = DownloadEntry.fromTask(record.task, taskStatus: record.status);
  if (!entry.visible && (entry.isActive || entry.canResume)) {
    // Cancel suppresses stale OS notifications; no files or records are deleted.
    if (!await cancel(entry.id)) {
      throw StateError('Could not stop an excluded legacy download.');
    }
  }
}

Future<void> replaceFailedDownload(
  Task old,
  DownloadTask replacement, {
  required Future<bool> Function(DownloadTask) enqueue,
  required Future<void> Function(String) deleteRecord,
}) async {
  if (!await enqueue(replacement)) {
    throw StateError(
      'Android rejected the replacement download; the old record was retained.',
    );
  }
  await deleteRecord(old.taskId);
}

/// Native WorkManager/UIDT jobs with the plugin's durable task database.
/// No database auto-cleanup: completed downloads remain in the offline library.
class DownloadService extends ChangeNotifier {
  DownloadService._();
  static final DownloadService instance = DownloadService._();
  static const group = 'reelbox.video';
  static const packageGroup = 'reelbox.offline.packages';
  final Map<String, DownloadEntry> _entries = {};
  final Set<String> _removing = {};
  Future<void>? _initialization;
  StreamSubscription<TaskRecord>? _databaseSubscription;
  AppState? _state;
  bool _ready = false;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  String? initializationError;
  List<DownloadEntry> get items {
    // Hide excluded legacy records without deleting the user's actual files.
    final result = _entries.values.where((e) => e.visible).toList()
      ..sort((a, b) => b.task.creationTime.compareTo(a.task.creationTime));
    return List.unmodifiable(result);
  }

  FileDownloader get _downloader => FileDownloader();

  /// Optional live settings binding; otherwise read durable AppState settings
  /// before each enqueue so the public enqueue signature needs no context.
  void bindSettings(AppState state) {
    if (identical(_state, state)) return;
    _state?.removeListener(_settingsChanged);
    _state = state;
    state.addListener(_settingsChanged);
    _settingsChanged();
  }

  void _settingsChanged() {
    if (_state != null) {
      configureNotifications(_state!.prefs.downloadNotifications);
    }
    if (_ready) {
      unawaited(
        _applyNetworkPolicy().catchError((Object e) {
          initializationError = 'Could not apply download network settings.';
          notifyListeners();
        }),
      );
    }
  }

  Future<AppSettings> _preferences() async {
    if (_state != null) return _state!.prefs;
    final storage = await SharedPreferences.getInstance();
    final raw = storage.getString(AppState.storageKey);
    if (raw == null) return AppSettings();
    final library = jsonDecode(raw) as Map<String, dynamic>;
    return AppSettings.fromJson(
      Map<String, dynamic>.from(library['settings'] as Map),
    );
  }

  Future<void> _applyNetworkPolicy() async {
    final prefs = await _preferences();
    final ok = await _downloader.requireWiFi(
      prefs.wifiOnlyDownloads
          ? RequireWiFi.forAllTasks
          : RequireWiFi.forNoTasks,
    );
    if (!ok) {
      throw StateError(
        'The OS could not update the download network constraint.',
      );
    }
  }

  Future<void> initialize() {
    if (!supported) {
      initializationError =
          'Background video downloads are available on Android only.';
      return Future.value();
    }
    return _initialization ??= _initialize().catchError((
      Object error,
      StackTrace stack,
    ) {
      _initialization = null;
      initializationError =
          'Native download initialization failed. Retry on Android.';
      notifyListeners();
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _initialize() async {
    // Group callbacks avoid stealing the plugin's single-subscription stream.
    _downloader.registerCallbacks(
      group: group,
      taskStatusCallback: _status,
      taskProgressCallback: _progress,
    );
    _databaseSubscription ??= _downloader.database.updates.listen((record) {
      if (record.task.group == group) unawaited(_acceptRecord(record));
    });
    for (final record in await _downloader.database.allRecords(group: group)) {
      await retireExcludedDownload(
        record,
        cancel: _downloader.cancelTaskWithId,
      );
    }
    await _downloader.start(autoCleanDatabase: false);
    await _applyNetworkPolicy();
    for (final record in await _downloader.database.allRecords(group: group)) {
      await _acceptRecord(record);
    }
    for (final package in await files.recoverPackages()) {
      _acceptPackage(package);
    }
    configureNotifications((await _preferences()).downloadNotifications);
    _ready = true;
    initializationError = null;
    notifyListeners();
  }

  bool _notificationsEnabled = true;
  TaskNotificationConfig? get notificationConfigForNewTask =>
      downloadNotificationConfig(_notificationsEnabled);

  /// Task-scoped configuration prevents stale group templates from leaking into
  /// new downloads after the preference is disabled. Active OS jobs keep their
  /// original notification policy until they finish.
  void configureNotifications(bool enabled) {
    _notificationsEnabled = enabled;
  }

  Future<void> refresh() async {
    if (!supported) {
      throw UnsupportedError('Download refresh requires Android.');
    }
    await initialize();
    final before = Map<String, DownloadEntry>.of(_entries);
    final snapshot = await readDownloadEntries(
      () => _downloader.database.allRecords(group: group),
    );
    final ids = snapshot.map((entry) => entry.id).toSet();
    for (final entry in snapshot) {
      // A native callback that arrived during I/O is newer than this snapshot.
      if (_removing.contains(entry.id) ||
          !identical(_entries[entry.id], before[entry.id])) {
        continue;
      }
      _entries[entry.id] = entry;
    }
    _entries.removeWhere(
      (id, entry) =>
          !entry.isSegmented &&
          !ids.contains(id) &&
          identical(entry, before[id]) &&
          !entry.isActive,
    );
    notifyListeners();
  }

  Future<void> _acceptRecord(TaskRecord record) async {
    if (_removing.contains(record.taskId)) return;
    await retireExcludedDownload(record, cancel: _downloader.cancelTaskWithId);
    final previous = _entries[record.taskId];
    final path = await record.task.filePath();
    if (_removing.contains(record.taskId)) return;
    // A progress callback may have overtaken asynchronous path resolution.
    final latest = _entries[record.taskId];
    if (latest != null && !identical(latest, previous)) return;
    _entries[record.taskId] = DownloadEntry.fromTask(
      record.task,
      taskStatus: record.status,
      progress: record.progress,
      totalBytes: record.expectedFileSize,
      path: path,
      speed: previous?.speed ?? 0,
      error: record.exception?.description ?? '',
    );
    notifyListeners();
  }

  void _status(TaskStatusUpdate update) {
    if (_removing.contains(update.task.taskId)) return;
    final old = _entries[update.task.taskId];
    _entries[update.task.taskId] = DownloadEntry.fromTask(
      update.task,
      taskStatus: update.status,
      progress: old?.progress ?? 0,
      totalBytes: old?.totalBytes ?? 0,
      path: old?.path ?? '',
      error: update.exception?.description ?? '',
    );
    notifyListeners();
  }

  void _progress(TaskProgressUpdate update) {
    if (_removing.contains(update.task.taskId)) return;
    final old = _entries[update.task.taskId];
    _entries[update.task.taskId] = DownloadEntry.fromTask(
      update.task,
      taskStatus: old?.taskStatus ?? TaskStatus.running,
      progress: update.progress >= 0 ? update.progress : old?.progress ?? 0,
      totalBytes: update.expectedFileSize > 0
          ? update.expectedFileSize
          : old?.totalBytes ?? 0,
      path: old?.path ?? '',
      speed: update.hasNetworkSpeed ? update.networkSpeed * 1000000 : 0,
      error: old?.error ?? '',
    );
    notifyListeners();
  }

  Future<void> enqueue({
    required TitleRecord title,
    required MediaSource source,
    EpisodeRecord? episode,
  }) async {
    if (!supported) {
      throw UnsupportedError('Background downloads require the Android app.');
    }
    if (title.id <= 0 ||
        title.title.trim().isEmpty ||
        !ContentPolicy.allowsTitleJson(title.toJson()) ||
        !ContentPolicy.allowsText(episode?.title ?? '') ||
        !ContentPolicy.allowsUrl(source.url)) {
      throw UnsupportedError(
        'This title or destination is excluded from Reelbox.',
      );
    }
    if (!isRemoteMedia(source.url) ||
        RegExp(
          r'drm|widevine|playready|fairplay|protected',
          caseSensitive: false,
        ).hasMatch(source.type)) {
      throw UnsupportedError(
        'Only authorized, non-DRM HTTP(S) media can be downloaded.',
      );
    }
    await initialize();
    await _applyNetworkPolicy();
    if (_entries.values.any(
      (entry) =>
          entry.url == source.url &&
          (entry.isActive || entry.canResume || entry.isComplete),
    )) {
      throw StateError('This source is already in Downloads.');
    }
    final prefs = await _preferences();
    configureNotifications(prefs.downloadNotifications);
    if (prefs.downloadNotifications &&
        await _downloader.permissions.status(PermissionType.notifications) !=
            PermissionStatus.granted) {
      await _downloader.permissions.request(PermissionType.notifications);
    }
    final id =
        '${title.id}_${episode?.id ?? 0}_${DateTime.now().microsecondsSinceEpoch}';
    final task = createDirectDownloadTask(
      id: id,
      title: title,
      source: source,
      preferences: prefs,
      episode: episode,
    );
    if (_segmentedSource(source)) {
      if (prefs.wifiOnlyDownloads && !_downloader.isWiFi) {
        throw StateError(
          'Connect to Wi-Fi before preparing an offline package.',
        );
      }
      final snapshot = await files.preparePackage(
        id: id,
        url: source.url,
        type: source.type,
        parallel: prefs.parallelDownloads,
        metadata: {
          'task': task.copyWith(group: packageGroup).toJson(),
          'notifications': prefs.downloadNotifications,
        },
      );
      _acceptPackage(snapshot);
      _startPackage(id);
      return;
    }
    final enqueued = await _downloader.enqueue(task);
    if (!enqueued) {
      throw StateError('Android rejected the background download job.');
    }
    // Read back the exact persistent task instead of calling queued success complete.
    final record = await _downloader.database.recordForId(task.taskId);
    if (record != null) {
      await _acceptRecord(record);
    } else {
      _entries.putIfAbsent(id, () => DownloadEntry.fromTask(task));
      notifyListeners();
    }
  }

  static bool _segmentedSource(MediaSource source) =>
      isSegmentedMediaSource(source);
  final _packageRuns = <String>{};
  void _acceptPackage(Map<String, dynamic> snapshot) {
    final metadata = Map<String, dynamic>.from(snapshot['metadata'] as Map);
    final original = Task.createFromJson(
      Map<String, dynamic>.from(metadata['task'] as Map),
    );
    final task = original.copyWith(filename: snapshot['manifest'] as String);
    if (_removing.contains(task.taskId)) return;
    final status = TaskStatus.values.firstWhere(
      (s) => s.name == snapshot['status'],
      orElse: () => TaskStatus.failed,
    );
    final bytes = (snapshot['receivedBytes'] as num?)?.toInt() ?? 0;
    _entries[task.taskId] = DownloadEntry.fromTask(
      task,
      taskStatus: status,
      progress: (snapshot['progress'] as num?)?.toDouble() ?? 0,
      receivedBytes: bytes,
      totalBytes: status == TaskStatus.complete ? bytes : 0,
      path: snapshot['path'] as String,
      error: snapshot['error'] as String? ?? '',
    );
    notifyListeners();
  }

  void _startPackage(String id) {
    if (!_packageRuns.add(id)) {
      throw StateError('This package is already active.');
    }
    unawaited(
      files
          .runPackage(id, _acceptPackage)
          .catchError((Object e) {
            final previous = _entries[id];
            if (previous != null && !_removing.contains(id)) {
              _entries[id] = DownloadEntry.fromTask(
                previous.task,
                taskStatus: TaskStatus.failed,
                path: previous.path,
                progress: previous.progress,
                receivedBytes: previous.receivedBytes,
                error: 'Offline package could not start: $e',
              );
              notifyListeners();
            }
          })
          .whenComplete(() => _packageRuns.remove(id)),
    );
  }

  /// Retries preserve the original URL/type, identity and notification policy.
  /// The old failed RECORD is removed only after successful new native enqueue;
  /// legacy user files are not removed as a side effect of replacing a record.
  Future<void> retry(DownloadEntry entry) async {
    await initialize();
    if (!entry.visible || entry.isActive || entry.canResume) {
      throw StateError('This download cannot be retried now.');
    }
    if (entry.isSegmented) {
      _startPackage(entry.id);
      return;
    }
    if (entry.task is! DownloadTask) {
      throw UnsupportedError('This task is not downloadable.');
    }
    final source = MediaSource(
      url: entry.url,
      quality: entry.quality,
      type: entry.sourceType,
    );
    if (_segmentedSource(source)) {
      await enqueue(
        title: entry.restoredTitle,
        source: source,
        episode: entry.episodeId == null
            ? null
            : EpisodeRecord(id: entry.episodeId!, title: entry.episodeTitle),
      );
      await _downloader.database.deleteRecordWithId(entry.id);
    } else {
      final id =
          '${entry.titleId}_${entry.episodeId ?? 0}_${DateTime.now().microsecondsSinceEpoch}';
      final next = (entry.task as DownloadTask).copyWith(
        taskId: id,
        filename: downloadFilename(
          title: entry.title,
          identity: id,
          url: entry.url,
        ),
        notificationConfig: downloadNotificationConfig(
          entry.downloadNotifications ?? false,
        ),
      );
      await replaceFailedDownload(
        entry.task,
        next,
        enqueue: _downloader.enqueue,
        deleteRecord: (id) async {
          await _downloader.database.deleteRecordWithId(id);
          if (await _downloader.database.recordForId(id) != null) {
            throw StateError('Could not replace the old download record.');
          }
        },
      );
      final record = await _downloader.database.recordForId(id);
      if (record != null) {
        await _acceptRecord(record);
      } else {
        _entries.putIfAbsent(id, () => DownloadEntry.fromTask(next));
      }
    }
    _entries.remove(entry.id);
    notifyListeners();
  }

  Future<void> reveal(DownloadEntry entry) async {
    final local = await offlinePath(entry);
    final path = entry.isSegmented
        ? await files.exportPackage(entry.id)
        : local;
    if (await MediaPlatform.invoke<bool>('revealFile', {'path': path}) !=
        true) {
      throw StateError(
        'No application could reveal or export this offline media.',
      );
    }
  }

  Future<void> externalDownloader(
    DownloadEntry entry, {
    String packageName = 'ask',
  }) async {
    if (!entry.visible || !isRemoteMedia(entry.url)) {
      throw UnsupportedError('This media cannot be handed off.');
    }
    if (_segmentedSource(MediaSource(url: entry.url, type: entry.sourceType))) {
      throw UnsupportedError(
        'Export a complete offline package instead; external downloaders may save only the manifest.',
      );
    }
    if (await MediaPlatform.invoke<bool>('openDownloader', {
          'url': entry.url,
          'filename': entry.filename,
          'packageName': packageName,
        }) !=
        true) {
      throw StateError('No external downloader could accept this file.');
    }
  }

  Future<void> pause(DownloadEntry entry) async {
    await initialize();
    if (entry.isSegmented) {
      await files.pausePackage(entry.id);
      _acceptPackage(await files.loadPackage(entry.id));
      return;
    }
    if (entry.task is! DownloadTask ||
        !await _downloader.pause(entry.task as DownloadTask)) {
      throw StateError(
        'Pause is unavailable. This server may not support byte ranges.',
      );
    }
  }

  Future<void> resume(DownloadEntry entry) async {
    await initialize();
    if (!entry.visible) {
      throw UnsupportedError('This legacy title is excluded from Reelbox.');
    }
    if (entry.isSegmented) {
      _startPackage(entry.id);
      return;
    }
    if (!await resumeDownloadTask(
      entry,
      configure: (task, config) => _downloader.configureNotificationForTask(
        task,
        running: config.running,
        complete: config.complete,
        error: config.error,
        paused: config.paused,
        progressBar: config.progressBar,
        tapOpensFile: config.tapOpensFile,
      ),
      resume: _downloader.resume,
    )) {
      throw StateError(
        'Cannot resume this task; remove it and start a new download.',
      );
    }
  }

  Future<void> cancel(DownloadEntry entry) async {
    await initialize();
    if (entry.isSegmented) {
      await files.pausePackage(entry.id, cancel: true);
      _acceptPackage(await files.loadPackage(entry.id));
      return;
    }
    if (!await _downloader.cancelTaskWithId(entry.id)) {
      throw StateError('The OS could not cancel this download.');
    }
  }

  Future<void> remove(DownloadEntry entry) async {
    await initialize();
    if (entry.isActive || entry.canResume) await cancel(entry);
    _removing.add(entry.id);
    try {
      if (entry.isSegmented) {
        await files.deletePackage(entry.id);
        _entries.remove(entry.id);
        notifyListeners();
        return;
      }
      final path = await entry.task.filePath();
      await files.delete(path);
      await _downloader.database.deleteRecordWithId(entry.id);
      if (await _downloader.database.recordForId(entry.id) != null) {
        throw StateError('Could not remove download record.');
      }
      _entries.remove(entry.id);
      notifyListeners();
    } finally {
      _removing.remove(entry.id);
    }
  }

  Future<String> offlinePath(DownloadEntry entry) async {
    if (!entry.visible) {
      throw UnsupportedError('This legacy title is excluded from Reelbox.');
    }
    if (!entry.isComplete) throw StateError('The download is not complete.');
    if (entry.isSegmented) {
      if (!await files.validatePackage(entry.id)) {
        throw StateError(
          'Offline package files are missing or damaged. Retry to repair.',
        );
      }
      return (await files.loadPackage(entry.id))['path'] as String;
    }
    final path = await entry.task.filePath();
    if (!await files.exists(path) ||
        entry.totalBytes > 0 && await files.size(path) != entry.totalBytes) {
      throw StateError(
        'The downloaded file is missing. Remove the entry and download again.',
      );
    }
    return path;
  }

  Future<void> open(DownloadEntry entry) async {
    final path = await offlinePath(entry);
    if (!await _downloader.openFile(filePath: path, mimeType: 'video/*')) {
      throw StateError(
        'No installed application could open this video. Use Play offline in Reelbox.',
      );
    }
  }
}
