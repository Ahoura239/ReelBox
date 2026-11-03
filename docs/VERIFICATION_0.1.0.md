# Reelbox 0.1.0 — verification and coverage

## Delivered build

- Application: **Reelbox**, package `org.reelbox.app`, version `0.1.0` / code `1`.
- APK: `reelbox-0.1.0-arm64.apk`, **38,109,881 bytes**.
- CPU: **arm64-v8a only**. Android minimum API **24**, target API **36**.
- APK SHA-256: `becb1b25935e46879c2cf2b7d4a34ad9c03cf3c3f74408669e761ec51bf694b4`.
- ZIP integrity check passed. ARM64 `libapp.so`, `libflutter.so` and `libmpv.so` are present; no dependency-only 32-bit/x86 ABI folders remain.
- APK signature verification passed using APK Signature Scheme v2 and a dedicated local release signer, **not Android's debug signer**. The private signing key/passwords are not included in source or delivery archives.

This is a **built beta**, not an on-device-tested or full-parity release.

## Executed checks

| Check | Actual result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test --concurrency=1 --reporter expanded` | **105 passed** |
| Release ARM64 APK build | Completed successfully |
| `apksigner verify --verbose --print-certs` | Verifies; dedicated release signer |
| `aapt dump badging` | Package/version/API/ARM64 metadata checked |
| APK ZIP integrity/core native libraries | Passed |
| Live read-only API smoke | Exit 0; real movie/episode sources, search and recommendations returned |
| Host-rendered English/Persian mobile UI | Four captures created and visually inspected |
| Android release lint | **Not run to completion; disabled for constrained-host packaging** |
| Physical Android installation/playback/background jobs | **Not verified** |

Curated real logs are in `docs/verification-logs/`. The latest live smoke inspected three movie details: two source-less newest entries, then a title with two sources. It also returned 30 movie records, 30 series records, one season with ten episode sources, five English-search results and 40 recommendations. No personal account was used and no video was downloaded. Link retrieval is not successful playback or permission to redistribute content.

## Review and regression history

The independent reports are retained as an audit trail, not silently rewritten as unconditional approvals:

- `independent-parity-baseline.json`: original static coverage review.
- `risk-review-before-fixes.json`: L001–L004 and previously disclosed transport risk.
- `review-fixes.json`: focused TDD corrections for restart notification policy, offline title identity, lifecycle cancellation and behavior-setting consumers.
- `re-review-before-global-fix.json`: confirms L001–L004 but identifies cross-player teardown ownership.
- `global-ownership-review-before-brightness-fix.json`: confirms ownership correction and identifies brightness-baseline handoff.

The final source adds shared global-control serialization/ownership and preserves the original activity brightness baseline across player handoffs. Both global setup/disposal orderings and the brightness-baseline regression were observed failing before correction, then passed. The full final suite includes these tests. This deterministic/mocked-channel evidence does **not** establish physical Android system-UI behavior.

Build failures were not treated as success: earlier attempts hit kernel/Java memory limits, release-lint timeout, an orphaned Gradle cache lock and a missing Java registration for an unused `integration_test` development dependency. The unused dependency was removed, registration regenerated, and the eventual APK was built and verified. An intermediate APK's extra dependency-only ABIs were rejected and corrected with explicit ABI filtering before delivery.

## Full feature parity remains unfinished

`feature-parity.json` tracks **229 original feature rows: 180 scoped and 49 intentionally excluded** by the account-free requirement. It records baseline assessments plus incremental implementation/test evidence. **No row is promoted to proof of every original behavior, and full parity is not claimed.**

Major missing areas still include Google Cast, segmented HLS/DASH offline assembly, background audio/media-session service, several original thematic/franchise/shared discovery features, web/shop/browser integrations, advanced subtitle preferences, file-manager reveal and startup introduction/update flows. See `KNOWN_LIMITATIONS.md` for details.

No accounts, registration, subscriptions, billing, payment UI, private lists or remote posting/rating submissions were added. Local collections/history and public read-only lists/comments are the intended alternatives.

## Release limitations

Java/resource shrinking and automatic release-lint tasks are disabled for this constrained-host beta build; Dart remains AOT release mode. Run native Android lint on a larger build machine before production/store distribution. Legacy HTTP media/artwork is still a disclosed privacy/integrity risk. Server-side access denials and DRM are not bypassed.

The source archive includes locked dependencies, build/signing instructions, tests, coverage reports and UI evidence. It excludes build caches, machine-local SDK paths and all private signing material. Source/archive hashes and the final packaging timestamp are recorded in the external delivery `verification.json` and `SHA256SUMS.txt`.
