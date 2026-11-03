# background_downloader 9.6.5 — RM003 patch

This is a runtime-only vendoring of the exact published `background_downloader`
9.6.5 package, not a general dependency upgrade. `lib/`, `android/`, `ios/`,
`pubspec.yaml`, and `LICENSE` were copied from that pinned package. Examples,
upstream tests, and documentation are omitted to keep the fork small.

- Upstream: https://github.com/781flyingdutchman/background_downloader
- Published archive: https://pub.dev/api/archives/background_downloader-9.6.5.tar.gz
- Published archive SHA-256 (original application lockfile and pub cache):
  `4df9b2a2d5b78b883ebd4b6338cbc1b541ea3482da24112339468a66a7492b43`
- Upstream `LICENSE` is retained verbatim, including its BSD-3-Clause terms and
  the bundled localstore MIT notice. Preserve these notices in redistribution.
- Package version remains `9.6.5`; the root application's path override selects
  this reviewed copy.

## Only production changes

1. `lib/src/chunk.dart`: `resumeChunkTasks` resumes only chunks whose serialized
   status is not `TaskStatus.complete`. A completed chunk's final file and status
   must remain available to the real parent stitching worker. Completed chunks
   have no resume data; trying to resume them returns false and cancels the parent.
2. `lib/src/desktop/desktop_downloader.dart`: read and retain the parent's resume
   snapshot before enqueue. Enqueue starts a desktop worker which consumes that
   record; rereading after enqueue races the worker and can return null. This
   separate race was reproduced while exercising the actual Linux workers.

All Android/iOS source files and every other runtime Dart file are byte-identical
to the pinned package. No package-cache or application-native source was edited.

## Verification

From the application root, with Flutter on PATH:

```sh
flock .tooling.lock flutter test --no-pub --concurrency=1 --reporter=expanded \
  --dart-define=flutter.dart_plugin_registrant=file://$PWD/test/download_multipart_http_test.dart \
  test/download_multipart_http_test.dart
```

The test file contains a real engine `_PluginRegistrant` which registers only the
installed Linux path provider. Flutter 3.47.9's `flutter_tester` does not otherwise
attach the Dart registrant to background isolates. Registering every generated
Linux plugin would additionally require unavailable host NetworkManager/DBus
services. Only storage/connectivity are fixtures; HTTP, three real ranges,
background isolates, pause/resume, callbacks, file stitching, and SHA-256 checks
run through this package unchanged apart from the two corrections above.

Tests cover uninterrupted transfer, pause after one fast chunk completed while
two nonempty partial chunks remain, and the same resume after writing/reading
fresh paused-task/resume JSON objects from disk. Assertions require five total
GET ranges after resume, exact saved resume offsets, no re-download of the
completed range, and identical complete output bytes and SHA-256.

These are Linux host integration tests, not Android WorkManager/device evidence
and not process-kill/restart evidence. Disk JSON rehydration is explicitly not a
claim of restarting the process. Parent Android build/device verification remains
necessary.
