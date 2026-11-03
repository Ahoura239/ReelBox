# Reelbox 0.2.0

An independent, Android-first Flutter app for films, series and a device-local library. No accounts, registration or subscriptions. This is not an official client and it is **not a full-parity replacement** for the original inspected application.

**[Download the signed ARM64 APK](https://reelbox.dartty.top:8443/downloads/reelbox-0.2.0-arm64.apk)** · **[Website](https://reelbox.dartty.top:8443/)** · [Verification](docs/VERIFICATION.md) · [Known limitations](docs/KNOWN_LIMITATIONS.md)

## License

Reelbox's original code is licensed under **GNU GPL version 3 only** (`GPL-3.0-only`); see [LICENSE](LICENSE). Third-party code, SDK components, fonts and design-process material retain their own licenses and notices. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), the [dependency inventory](third_party/DEPENDENCIES.json)

## Account-free scope

- No login, registration, subscriptions, billing or personal API credentials.
- Public catalog, source discovery and recommendations use operator-supplied build-time service keys. These are shared service credentials, not personal account credentials, and are intentionally absent from this repository.
- Saved titles, collections, history, search history and preferences stay on the device unless you explicitly export/share a backup.
- Read-only film/series comments do not enable posting, rating submission or private server lists. Live channels and public playlists are removed; private local collections and episode queues remain.
- 
## Development

The checked toolchain is Flutter 3.47.9 / Dart 3.13.7. Dependencies are locked in `pubspec.lock`. Android package: `org.reelbox.app`.

```sh
flutter pub get
python tool/verify_host.py
python tool/native_resource_fetch_test.py
flock .tooling.lock flutter test --concurrency=1 \
  --dart-define-from-file=/secure/path/api-defines.json tool/api_smoke_test.dart
```

A release build requires a dedicated signing identity. It never falls back to Android's debug signing key. Do not commit a keystore or signing passwords.

Create a PKCS12 keystore with `keytool` (the command prompts for its password):

```sh
keytool -genkeypair -keystore /secure/path/reelbox-release.p12 \
  -storetype PKCS12 -alias reelbox -keyalg RSA -keysize 3072 -validity 10000
```


```sh
export REELBOX_SIGNING_PROPERTIES=/secure/path/keystore.properties
flutter build apk --release --target-platform android-arm64 \
  --dart-define-from-file=/secure/path/api-defines.json
```


## Runtime and data boundaries

- Catalog traffic is restricted to trusted HTTPS API destinations and does not follow redirects carrying the client constant to untrusted hosts.
- Source/artwork URLs are supplied by the external service. Legacy HTTP media is currently permitted for compatibility; these requests are not confidential or protected against on-path modification. No personal account credentials are attached to them.
- Direct multipart downloads and bounded static non-DRM HLS/DASH offline packages are implemented. Unsupported protected/live/dynamic/unbounded manifests are rejected instead of saved as fake video files. Package/hash tests are not codec playback tests; disk-state rehydration is not process-kill/restart evidence.
- Cast sharing is explicit, temporary and limited to registered files or validated indexed package resources. Local subtitles are converted to real WebVTT. Embedded/automatic decoder tracks cannot be extracted for Cast; explicitly selected unsupported tracks are reported rather than silently reusing old external text.
- First-run onboarding, private watched markers/history, discovery/search helpers, subtitle preferences, scoped file export, external downloader/player handoff and an opt-in background-media bridge are included. Native behavior remains device-unverified for this release.
- Only schema-verified trusted HTTPS configuration is cached. Read-only GET transport failures get at most one replay; HTTP denials/errors, cancellation, certificate failures and POSTs are not automatically retried. The allowlist currently contains one service host; no alternate domains are invented.
- No automatic app-update installer is provided. Do not install updates from untrusted sources.
- Android playback, notifications, background job recovery, PiP, external app intents, subtitles and system controls require actual device verification. Passing Dart/widget tests or producing an APK is not evidence that these native behaviors work.
