// Console output is intentional evidence from this real-worker test fixture.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
// flutter_tester does not attach the generated Dart plugin registrant in
// Flutter 3.47.9. Include the engine lookup constant and host-only registrar.
// Run under the shared compiler lock, with test concurrency=1:
// flock .tooling.lock flutter test --concurrency=1 \
//   --dart-define=flutter.dart_plugin_registrant=file://$PWD/test/download_multipart_http_test.dart \
//   test/download_multipart_http_test.dart
// ignore: implementation_imports, unused_import
import 'package:flutter/src/dart_plugin_registrant.dart';
// The installed Linux path provider bootstraps real worker isolates only.
// ignore: depend_on_referenced_packages
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/media/download_service.dart';
import 'package:reelbox/state/app_state.dart';

// The engine invokes this in every real downloader isolate. Do not register
// connectivity_plus's DBus backend: the headless test host has no NetworkManager.
@pragma('vm:entry-point')
class _PluginRegistrant {
  @pragma('vm:entry-point')
  static void register() => PathProviderLinux.registerWith();
}

// Only host persistence/connectivity are fixtures. HTTP, range splitting,
// worker isolates, pause/resume, callbacks and stitching are real plugin code.
class _Storage implements PersistentStorage {
  final records = <String, TaskRecord>{},
      paused = <String, Task>{},
      resumes = <String, ResumeData>{};
  @override
  (String, int) get currentDatabaseVersion => ('fixture', 1);
  @override
  Future<(String, int)> get storedDatabaseVersion async =>
      currentDatabaseVersion;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> storeTaskRecord(TaskRecord r) async {
    records[r.taskId] = r;
  }

  @override
  Future<TaskRecord?> retrieveTaskRecord(String id) async => records[id];
  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() async =>
      records.values.toList();
  @override
  Future<void> removeTaskRecord(String? id) async {
    id == null ? records.clear() : records.remove(id);
  }

  @override
  Future<void> storePausedTask(Task t) async {
    paused[t.taskId] = t;
  }

  @override
  Future<Task?> retrievePausedTask(String id) async => paused[id];
  @override
  Future<List<Task>> retrieveAllPausedTasks() async => paused.values.toList();
  @override
  Future<void> removePausedTask(String? id) async {
    id == null ? paused.clear() : paused.remove(id);
  }

  @override
  Future<void> storeResumeData(ResumeData r) async {
    resumes[r.taskId] = r;
  }

  @override
  Future<ResumeData?> retrieveResumeData(String id) async => resumes[id];
  @override
  Future<List<ResumeData>> retrieveAllResumeData() async =>
      resumes.values.toList();
  @override
  Future<void> removeResumeData(String? id) async {
    id == null ? resumes.clear() : resumes.remove(id);
  }

  // Reconstitute fresh task/resume objects from actual disk JSON, not merely
  // another reference to the same objects. This is not a process restart test.
  Future<void> reloadResumeSnapshot(File file) async {
    await file.writeAsString(
      jsonEncode({
        'paused': paused.values.map((t) => t.toJson()).toList(),
        'resumes': resumes.values.map((r) => r.toJson()).toList(),
      }),
      flush: true,
    );
    paused.clear();
    resumes.clear();
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    for (final value in json['paused'] as List) {
      final task = Task.createFromJson(value as Map<String, dynamic>);
      paused[task.taskId] = task;
    }
    for (final value in json['resumes'] as List) {
      final resume = ResumeData.fromJson(value as Map<String, dynamic>);
      resumes[resume.taskId] = resume;
    }
  }
}

Future<void> _until(FutureOr<bool> Function() predicate, String reason) async {
  final watch = Stopwatch()..start();
  while (!await predicate()) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      fail('Timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _RangeFixture {
  static const chunkLength = 262144;
  final bytes = Uint8List.fromList(
    List.generate(chunkLength * 3, (i) => i % 251),
  );
  final ranges = <(int, int)>[];
  final errors = <Object>[];
  final handlers = <Future<void>>[];
  final bool throttle;
  late final HttpServer server;
  late final Directory root;
  var active = 0, peak = 0;
  var closing = false;
  final shutdown = Completer<void>();

  _RangeFixture({this.throttle = false});

  Future<void> start() async {
    root = await Directory.systemTemp.createTemp('reelbox-multipart-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => handlers.add(_serve(request)));
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.headers.set('accept-ranges', 'bytes');
    response.headers.set('content-type', 'video/mp4');
    response.headers.set('etag', '"reelbox-fixture-v1"');
    if (request.method == 'HEAD') {
      response.contentLength = bytes.length;
      await response.close();
      return;
    }
    final match = RegExp(r'^bytes=(\d+)-(\d*)$')
        .firstMatch(request.headers.value('range') ?? '');
    if (match == null) {
      errors.add(StateError('Expected an actual range request'));
      response.statusCode = 400;
      await response.close();
      return;
    }
    final start = int.parse(match[1]!);
    final end = match[2]!.isEmpty ? bytes.length - 1 : int.parse(match[2]!);
    ranges.add((start, end));
    response.statusCode = 206;
    response.headers.set('content-range', 'bytes $start-$end/${bytes.length}');
    response.contentLength = end - start + 1;
    active++;
    if (active > peak) peak = active;
    try {
      // Range zero finishes first; two other workers genuinely transfer bytes
      // slowly so the parent can pause only after the fast worker completed.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final step = throttle && start >= chunkLength ? 4096 : end - start + 1;
      for (var offset = start; offset <= end && !closing; offset += step) {
        final next = offset + step > end + 1 ? end + 1 : offset + step;
        response.add(bytes.sublist(offset, next));
        // A paused worker stops consuming the old response. On teardown,
        // cancel that server-side wait too; force-close alone can strand flush.
        await Future.any([response.flush(), shutdown.future]);
        if (step == 4096) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
      if (!closing) await Future.any([response.close(), shutdown.future]);
    } on SocketException catch (error) {
      // Pause closes the real worker's connection partway through a response.
      if (!throttle && !closing) errors.add(error);
    } on HttpException catch (error) {
      if (!throttle && !closing) errors.add(error);
    } finally {
      active--;
    }
  }

  DownloadTask task(String id) => createDirectDownloadTask(
    id: id,
    title: const TitleRecord(id: 8, title: 'Fixture'),
    source: MediaSource(url: 'http://127.0.0.1:${server.port}/video.mp4'),
    preferences: AppSettings(
      parallelDownloads: 3,
      downloadNotifications: false,
    ),
  ).copyWith(baseDirectory: BaseDirectory.root, directory: root.path);

  Future<void> verify(DownloadTask task) async {
    final actual = await File(await task.filePath()).readAsBytes();
    expect(actual.length, bytes.length);
    expect(actual, orderedEquals(bytes));
    expect(sha256.convert(actual), sha256.convert(bytes));
    expect(errors, isEmpty);
    expect(peak, greaterThan(1));
    print(
      '[multipart-result] ${task.taskId}: bytes=${actual.length} '
      'sha256=${sha256.convert(actual)} ranges=$ranges peak=$peak',
    );
  }

  Future<void> close() async {
    closing = true;
    shutdown.complete();
    await server.close(force: true);
    await Future.wait(handlers);
    await root.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = _Storage();
  late FileDownloader downloader;
  final previousPlatform = debugDefaultTargetPlatformOverride;
  final previousHttp = HttpOverrides.current;

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    HttpOverrides.global = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
    downloader = FileDownloader(persistentStorage: storage);
    await downloader.ready;
  });
  tearDownAll(() {
    downloader.destroy();
    debugDefaultTargetPlatformOverride = previousPlatform;
    HttpOverrides.global = previousHttp;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
  });
  setUp(() {
    Logger.root.level = Level.ALL;
    final logs = Logger.root.onRecord.listen((record) {
      print(
        '[multipart] ${record.loggerName} ${record.level}: ${record.message}',
      );
      if (record.error != null) print(record.error);
      if (record.stackTrace != null) print(record.stackTrace);
    });
    addTearDown(logs.cancel);
  });

  test(
    'uninterrupted real three-range transfer stitches exact bytes and SHA-256',
    () async {
      final fixture = _RangeFixture();
      await fixture.start();
      addTearDown(fixture.close);
      await downloader.configure(
        desktopConfig: (Config.tempFilePath, fixture.root.path),
      );
      final task = fixture.task('multipart-uninterrupted');
      expect(task, isA<ParallelDownloadTask>());
      final result = await downloader
          .download(task, onProgress: (_) {})
          .timeout(const Duration(seconds: 20));
      expect(
        result.status,
        TaskStatus.complete,
        reason: result.exception?.description,
      );
      await fixture.verify(task);
      expect(fixture.ranges.toSet(), {
        (0, _RangeFixture.chunkLength - 1),
        (_RangeFixture.chunkLength, _RangeFixture.chunkLength * 2 - 1),
        (_RangeFixture.chunkLength * 2, fixture.bytes.length - 1),
      });
      expect(fixture.ranges, hasLength(3));
    },
  );

  for (final reload in [false, true]) {
    test(
      'resume after fast chunk completed preserves bytes/hash${reload ? ' with disk JSON rehydration' : ''}',
      () async {
        final fixture = _RangeFixture(throttle: true);
        await fixture.start();
        addTearDown(fixture.close);
        await downloader.configure(
          desktopConfig: (Config.tempFilePath, fixture.root.path),
        );
        final task = fixture.task(
          reload ? 'multipart-rehydrated' : 'multipart-resume',
        );
        final statuses = <TaskStatus>[];
        final complete = Completer<TaskStatusUpdate>();
        downloader.registerCallbacks(
          group: task.group,
          taskProgressCallback: (_) {},
          taskStatusCallback: (update) {
            if (update.task.taskId != task.taskId) return;
            statuses.add(update.status);
            if (update.status.isFinalState && !complete.isCompleted) {
              complete.complete(update);
            }
          },
        );
        final chunks = <Task>[];
        addTearDown(() async {
          await downloader.cancelTasksWithIds([
            task.taskId,
            ...chunks.map((t) => t.taskId),
          ]);
          await _until(
            () async =>
                (await downloader.allTasks(allGroups: true))
                    .where((t) => t.taskId == task.taskId || chunks.contains(t))
                    .isEmpty,
            'worker cleanup',
          );
          downloader.unregisterCallbacks(group: task.group);
          for (final chunk in chunks) {
            final file = File(await chunk.filePath());
            if (await file.exists()) await file.delete();
          }
          storage.paused.clear();
          storage.resumes.clear();
        });
        expect(await downloader.enqueue(task), isTrue);
        await _until(() async {
          chunks.clear();
          chunks.addAll(
            await downloader.allTasks(group: FileDownloader.chunkGroup),
          );
          return chunks.length == 3;
        }, 'three real chunk workers');
        final fast = chunks.singleWhere(
          (t) =>
              t.headers['Range'] == 'bytes=0-${_RangeFixture.chunkLength - 1}',
        );
        await _until(
          () async =>
              await File(await fast.filePath()).exists() &&
              !(await downloader.allTasks(group: FileDownloader.chunkGroup))
                  .contains(fast),
          'fast chunk file and worker completion',
        );
        await _until(() async {
          var partials = 0;
          await for (final entry in fixture.root.list()) {
            if (entry is File &&
                entry.path.split('/').last.startsWith('com.bbflight.')) {
              final length = await entry.length();
              if (length > 0 && length < _RangeFixture.chunkLength) partials++;
            }
          }
          return partials == 2;
        }, 'both slow chunks to have actually written partial bytes');
        expect(await downloader.pause(task), isTrue);
        await _until(
          () =>
              statuses.contains(TaskStatus.paused) &&
              storage.resumes.containsKey(task.taskId) &&
              chunks
                  .where((t) => t != fast)
                  .every((t) => storage.resumes.containsKey(t.taskId)),
          'parent and unfinished chunk resume records',
        );
        // The completed status is produced by the actual parent worker, not injected.
        final savedChunks =
            jsonDecode(storage.resumes[task.taskId]!.data) as List;
        final savedFast = savedChunks.cast<Map<String, dynamic>>().singleWhere(
          (c) => c['fromByte'] == 0,
        );
        expect(savedFast['status'], TaskStatus.complete.index);
        expect(storage.resumes.containsKey(fast.taskId), isFalse);
        expect(
          await File(await fast.filePath()).readAsBytes(),
          orderedEquals(fixture.bytes.sublist(0, _RangeFixture.chunkLength)),
        );
        final unfinished = chunks.where((t) => t != fast).toList();
        final expectedResumedRanges = unfinished.map((t) {
          final resume = storage.resumes[t.taskId]!;
          expect(resume.requiredStartByte, greaterThan(0));
          expect(resume.eTag, '"reelbox-fixture-v1"');
          final original = RegExp(r'bytes=(\d+)-(\d+)')
              .firstMatch(t.headers['Range']!)!;
          return (
            int.parse(original[1]!) + resume.requiredStartByte,
            int.parse(original[2]!),
          );
        }).toSet();
        expect(fixture.ranges, hasLength(3));
        print(
          '[multipart-paused] ${task.taskId}: completed=1 unfinished=2 '
          'completedResumeRecord=false resumeRanges=$expectedResumedRanges',
        );
        var resumeTask = task;
        if (reload) {
          await storage.reloadResumeSnapshot(
            File('${fixture.root.path}/resume.json'),
          );
          resumeTask = storage.paused[task.taskId]! as DownloadTask;
          expect(identical(resumeTask, task), isFalse);
        }
        expect(
          await downloader.resume(resumeTask),
          isTrue,
          reason:
              'Completed chunks have no resume data and must not be resumed',
        );
        final result = await complete.future.timeout(
          const Duration(seconds: 20),
        );
        expect(
          result.status,
          TaskStatus.complete,
          reason: result.exception?.description,
        );
        expect(
          statuses,
          containsAllInOrder([
            TaskStatus.running,
            TaskStatus.paused,
            TaskStatus.running,
            TaskStatus.complete,
          ]),
        );
        await fixture.verify(task);
        expect(fixture.ranges, hasLength(5));
        expect(fixture.ranges.skip(3).toSet(), expectedResumedRanges);
        expect(
          fixture.ranges.where((r) => r.$1 == 0),
          hasLength(1),
          reason: 'The completed chunk must be reused, not downloaded again',
        );
      },
    );
  }
}
