# Third-party notices

The top-level GPL-3.0-only license applies to Reelbox's original application and supporting code. Existing third-party notices are preserved; the top-level license does not replace them or grant rights in external media.

## Dart and Flutter

`pubspec.lock` identifies the resolved versions. `third_party/DEPENDENCIES.json` maps every resolved Dart/Flutter package to its upstream and retained license text in `third_party/licenses/dart/`. This includes build/test-only packages as well as runtime packages. Flutter and Dart SDKs are obtained separately, not redistributed in this repository.

The local `third_party/background_downloader/` tree is version 9.6.5 under its retained BSD-3-Clause license. The two Dart-only multipart resume fixes are described in `VENDORED.md`; original copyright/license notices remain in place.

## Native media and Android libraries

The MIT-licensed `media_kit_libs_android_video` 1.3.8 Flutter plugin obtains its native ARM64 library from the **v1.1.7** build at https://github.com/media-kit/libmpv-android-video-build. Its exact download URL and checksum are specified in that package's `android/build.gradle`.

The plugin's MIT license must **not** be mistaken for the licenses of bundled mpv, FFmpeg and their codec/subtitle libraries. Their upstream source/build recipes and component license notices remain applicable. Native build recipes: https://github.com/media-kit/libmpv-android-video-build/tree/v1.1.7. mpv source: https://github.com/mpv-player/mpv. FFmpeg source: https://ffmpeg.org/download.html. Consult those exact component revisions/build recipes before redistributing a modified native stack.

Android platform/support libraries and Google Play services Cast Framework are separately resolved by Gradle. Direct native dependencies are pinned in `android/app/build.gradle.kts`; Gradle/Android SDK components are not relicensed by the project's GPL grant. See their distributed notices and applicable upstream terms. This inventory is not a certification of every possible dependency combination or app-store eligibility.

The Material Icons font is a Flutter-provided asset under its own Apache-2.0 notice, retained in `third_party/licenses/material-icons.txt`.

## Website

The screenshot is a host-rendered capture of Reelbox's actual interface, not evidence of Android hardware behavior. It contains no third-party film artwork.

Design process: **Unslop by Damir Sokolovsky (@heydamir)**, https://heydamir.design/unslop, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). The website is an original implementation using that process, not a copy of the upstream reference layouts. Credit is also retained in the page and `website/DESIGN.md`.
