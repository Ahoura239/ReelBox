# Reelbox 0.2.0

An independent, Android-first Flutter app for films, series and a device-local library. No accounts, registration or subscriptions. This is not an official client and it is **not a full-parity replacement** for the original inspected application.

**[Download the signed ARM64 APK](https://reelbox.dartty.top/downloads/reelbox-0.2.0-arm64.apk)** · **[Website](https://reelbox.dartty.top/)** · [Verification](docs/VERIFICATION.md) · [Known limitations](docs/KNOWN_LIMITATIONS.md)

## License

Reelbox's original code is licensed under **GNU GPL version 3 only** (`GPL-3.0-only`); see [LICENSE](LICENSE). Third-party code, SDK components, fonts and design-process material retain their own licenses and notices. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), the [dependency inventory](third_party/DEPENDENCIES.json), and the vendored downloader's license. The GPL grant does not cover external catalog artwork, metadata or media.

## Account-free scope

- No login, registration, subscriptions, billing or personal API credentials.
- Public catalog, source discovery and recommendations use operator-supplied build-time service keys. These are shared service credentials, not personal account credentials, and are intentionally absent from this repository.
- Saved titles, collections, history, search history and preferences stay on the device unless you explicitly export/share a backup.
- Read-only film/series comments do not enable posting, rating submission or private server lists. Live channels and public playlists are removed; private local collections and episode queues remain.
- Original-service support/community/news/Telegram/promotional/updater surfaces are excluded. App sharing sends independent Reelbox information, not an invented installation URL.
- A returned URL does not establish permission to download or redistribute a work. Use content you are entitled to access. Server authentication, authorization, DRM and playback denials are not bypassed.
- No original executable was run to extract the catalog. The export is a reconstructed API snapshot, not the server's physical database.

## Development

The checked toolchain is Flutter 3.47.9 / Dart 3.13.7. Dependencies are locked in `pubspec.lock`. Android package: `org.reelbox.app`.

```sh
flutter pub get
python tool/verify_host.py
python tool/native_resource_fetch_test.py
flock .tooling.lock flutter test --concurrency=1 \
  --dart-define-from-file=/secure/path/api-defines.json tool/api_smoke_test.dart
```

Unit/widget tests use controlled fixtures and work without live service keys. For actual service access, obtain keys from an authorized service operator and create a private JSON file outside the checkout containing the string fields `REELBOX_API_KEY` and `REELBOX_ACTOR_KEY`. The defaults are empty, **not a working public-service configuration**. Do not commit this file. Pass it to `flutter run`, the opt-in live smoke test or the release build with `--dart-define-from-file`.

The live API smoke test contacts the external service, requires network access and verifies catalog/details/search/recommendation response shapes. It does **not** download videos or prove that any media source plays. Unit/widget fixtures are explicitly test fixtures, not fabricated production data.

The live probe uses Flutter's runner because API configuration persistence uses a Flutter preference plugin. The opt-in wrapper replaces only the test framework's deliberately blocked HTTP client with the normal TLS-validating client; preference storage is a local fixture, and remote API responses are not mocked. The earlier plain `dart run tool/api_smoke.dart` command is no longer supported.

`verify_host.py` holds the tooling lock across analysis and all Flutter test files. Real Linux multipart-worker tests require a specific path-provider registrant and therefore run separately, not skipped. The runner records exact file coverage, case totals and exit codes. The native resource test acquires the same lock internally; do not wrap it in another `flock`.

The pinned downloader fork, its two narrow Dart fixes and retained license are documented in `third_party/background_downloader/VENDORED.md`. No native downloader source is changed.

On a memory-constrained host, serialize Flutter/Dart/Gradle commands. The working environment uses `flock .tooling.lock` before each Flutter command and one test worker.

## Android release build

A release build requires a dedicated signing identity. It never falls back to Android's debug signing key. Do not commit a keystore or signing passwords.

Create a PKCS12 keystore with `keytool` (the command prompts for its password):

```sh
keytool -genkeypair -keystore /secure/path/reelbox-release.p12 \
  -storetype PKCS12 -alias reelbox -keyalg RSA -keysize 3072 -validity 10000
```

Place these properties in a private file, readable only by the build owner:

```properties
storeFile=/secure/path/reelbox-release.p12
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=reelbox
```

```sh
export REELBOX_SIGNING_PROPERTIES=/secure/path/keystore.properties
flutter build apk --release --target-platform android-arm64 \
  --dart-define-from-file=/secure/path/api-defines.json
```

Without `REELBOX_SIGNING_PROPERTIES`, the build looks in `~/.config/reelbox-signing/keystore.properties`. The local delivery signer is independent of the original app and is not an app-store identity. Back up your own signing identity securely if you intend to distribute updates. Source archives do not include the private signing key.

The arm64 APK is for 64-bit ARM Android devices, not all Android CPU architectures. Its Gradle `defaultConfig.ndk.abiFilters` explicitly permits only `arm64-v8a`, so dependency-only libraries cannot advertise unsupported CPU architectures. For another architecture, change that filter **and** `--target-platform`; adjust/remove the explicit filter before using split APKs. Build output: `build/app/outputs/flutter-apk/app-release.apk`.

### Constrained-host packaging caveat

Java/resource shrinking is disabled in this source configuration, while Dart stays in AOT release mode. APKs are consequently larger. Automatic Android release-lint analysis is also disabled because dependency lint exhausted this build host's resources/time budget. **This does not mean Android lint passed.** Before app-store or production distribution, run `cd android && ./gradlew lintRelease` on a larger build machine and review its findings. Dart static analysis, Dart/widget tests, APK archive/signature verification and on-device testing are separate checks.

## Runtime and data boundaries

- Catalog traffic is restricted to trusted HTTPS API destinations and does not follow redirects carrying the client constant to untrusted hosts.
- Source/artwork URLs are supplied by the external service. Legacy HTTP media is currently permitted for compatibility; these requests are not confidential or protected against on-path modification. No personal account credentials are attached to them.
- Direct multipart downloads and bounded static non-DRM HLS/DASH offline packages are implemented. Unsupported protected/live/dynamic/unbounded manifests are rejected instead of saved as fake video files. Package/hash tests are not codec playback tests; disk-state rehydration is not process-kill/restart evidence.
- Cast sharing is explicit, temporary and limited to registered files or validated indexed package resources. Local subtitles are converted to real WebVTT. Embedded/automatic decoder tracks cannot be extracted for Cast; explicitly selected unsupported tracks are reported rather than silently reusing old external text.
- First-run onboarding, private watched markers/history, discovery/search helpers, subtitle preferences, scoped file export, external downloader/player handoff and an opt-in background-media bridge are included. Native behavior remains device-unverified for this release.
- Only schema-verified trusted HTTPS configuration is cached. Read-only GET transport failures get at most one replay; HTTP denials/errors, cancellation, certificate failures and POSTs are not automatically retried. The allowlist currently contains one service host; no alternate domains are invented.
- No automatic app-update installer is provided. Do not install updates from untrusted sources.
- Android playback, notifications, background job recovery, PiP, external app intents, subtitles and system controls require actual device verification. Passing Dart/widget tests or producing an APK is not evidence that these native behaviors work.

## Catalog export

The complete catalog bundle is delivered separately as `moviebox-catalog-complete.zip`. It contains source-link records and metadata, **not video files**. Preserve its manifest and extraction provenance with the dataset. Media links can expire or become unavailable independently of the snapshot.
