# Reelbox 0.2.0 — build and verification

## Verified artifact

- Application: **Reelbox**, package `org.reelbox.app`, version **0.2.0 / code 2**
- APK: `reelbox-0.2.0-arm64.apk`, **41,149,236 bytes**
- Android: minimum API **24**, target API **36**, **arm64-v8a only**
- SHA-256: `2c224625b0492d04a3fb7ead1c71710e29d91f5ea6da0818846159e4407f15d0`
- Dedicated signer: **CN=Reelbox Local Release**, not Android Debug; certificate matches the delivered 0.1.0 APK
- APK signature verification, ZIP integrity, package/version/API metadata and ABI checks passed
- ARM64 `libapp.so`, `libflutter.so`, `libmpv.so` present; no dependency-only extra ABIs or debug kernel

This is a signed beta with host verification, **not a current-release Android/Cast hardware validation or full original-behavior parity claim**. The user's reported Android installation/playback success applies to 0.1.0. The original beta APK/source and complete catalog export were preserved.

## Executed checks

| Check | Actual result |
|---|---|
| Complete Flutter host suite | **339 passed across all 49 test files**, no skipped multipart cases |
| Ordinary suite | 336 passed |
| Real multipart-worker suite | 3 passed in its required host-registrant invocation |
| Final `flutter analyze --no-pub` | No issues found |
| Real read-only catalog smoke | Passed through opt-in Flutter wrapper; remote responses not mocked |
| Android release Kotlin integration | Passed |
| `flutter build apk --release --target-platform android-arm64 --no-pub` | Passed; Gradle assemble completed in 1354.8 seconds |
| APK signature/package/version/ABI/native-library/ZIP checks | Passed; same signer as 0.1.0 |
| Native restricted-resource fixtures | 35 policy assertions and 9 resource cases passed; source-wiring checks passed |
| Current mobile English/Persian host UI capture | Passed; current More and Persian intro pixels inspected, with prior library/settings inspection |
| `git diff --check` | Passed |
| Runtime source fingerprints after full tests and build | No differences across 161 recorded inputs |
| Android native release lint | Not completed/enabled in this constrained-host build |
| Physical Android/Cast/background/PiP/OS process recovery | Not executed; no device attached |

The complete host runner enumerates all test files, holds `.tooling.lock`, and runs the actual multipart file separately with its required Linux path-provider registrant. The normal and special runs cover the same complete declared file set. Linux worker transfers verify exact 786,432-byte output, SHA-256, resumed offsets and no completed-range re-download. Disk JSON rehydration is not process-kill/restart evidence.

The live smoke returned 29 movie entries and 30 series entries; it inspected two real movie details, finding two sources in the second. It also found a series season with 28 episode sources, five English-search results and 39 recommendations. No personal account was used and no video was downloaded. These are response/source-availability checks, not decoder, authorization or redistribution tests.

## Review-driven corrections

The historical independent Cast review failed on four concrete logic defects. Its failed verdict is preserved. Fixes now have observed RED/GREEN and full-suite coverage:

1. Invalidate pending preparation on actual source, episode and subtitle changes, including before casting becomes true; close stale leases without casting old media
2. Restore the latest intended local playback after disconnect during the awaited pause, without resurrecting stop/released/new-owner/new-source playback
3. Preserve newer user play/pause intent on rejected or throwing loads; stale errors cannot overwrite newer state
4. Centralize file/service/existing-track subtitle selection, clear old external text for embedded/no selections and refresh active Cast safely

The scope audit additionally identified absent independent app sharing, ignored Stretch geometry and incomplete trusted configuration recovery. All three now have passing regressions. Earlier paging/gesture tests were updated to exercise real automatic prefetch and the production below-controls gesture surface, rather than weakening continuation, cursor, stale-response or dispatch assertions.

Provider rate limits interrupted two implementation workers. Partial work and logs were inspected and completed directly. There was **no fresh independent post-fix reviewer sign-off**; the passing tests are not presented as one.

## Scope and retained history

`CURRENT_SCOPE_0.2.0.json` maps all **164 retained/Android-adapted rows** and **65 exclusions** from the 229-row inventory. The original `feature-parity.json` keeps its provenance, baseline gaps and historical statuses; it is not the current implementation verdict. Desktop helper binaries, account features, public playlists/live channels and original vendor/support/news/Telegram/updater surfaces are not reintroduced to erase old parity labels.

Read-only film/series comments, private local collections and episode queues remain. No accounts, registration, subscriptions, billing, posting/rating submissions or advertising SDKs were added.

Historical 0.1.0 verification is preserved in `VERIFICATION_0.1.0.md`. Current logs and reports are under `verification-logs-0.2.0/`.

## Limitations and failed attempts retained honestly

- The original plain Dart smoke command stopped compiling once API persistence imported a Flutter preference plugin. The opt-in Flutter wrapper is the corrected working invocation. It replaces only Flutter test's blocked HTTP client with the normal TLS-validating client and fixtures only local preferences; API data remains real.
- Native lint and Java/resource shrinking remain disabled for constrained-host beta packaging; Dart is AOT release. This is not a lint pass. SDK XML/Gradle deprecation warnings occurred but did not fail the release build.
- Cast codec/manifest/subtitle support, native tracks/system controls, PiP, foreground media/notifications, installed external apps/file providers and OS process recovery still require current-build device tests.
- The restricted browser supports public GET/HEAD flows, not authenticated/POST-heavy embeds. Redirected HTML/CSS/module base-URL/CORS behavior remains device-unverified. No unsafe TLS or unchecked-network fallback is used.
- The configuration allowlist currently has one service host; persistence/retry does not invent alternative domains. HTTP denials/errors, certificate failures, cancellation and POSTs are not automatically replayed.
- Legacy external HTTP media/artwork remains a disclosed privacy/integrity tradeoff. DRM and access denials are not bypassed.

See `KNOWN_LIMITATIONS.md` for the detailed boundaries. Source archives exclude build caches, local SDK paths and private signing material; the downloader fork retains its original license and provenance.
