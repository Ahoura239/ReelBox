# Known limitations — 0.2.0 candidate

This is an independently branded, account-free Android film/series client. The delivered **0.1.0** APK has user-reported installation and playback success. That evidence does not establish playback, Cast, background execution or download recovery for the current **0.2.0** candidate.

## Release gates still open

- The independent Cast review identified four logic defects. All four now have code fixes and passing regressions, including actual page source/episode/subtitle changes, cancellation/owner handoffs and newer play/pause intent. The historical failed review is preserved, not relabeled as an approval; no fresh independent post-fix sign-off was obtained after provider rate limits.
- The post-fix host verification passed **339 tests across all 49 Flutter test files**, with clean analysis. `tool/verify_host.py` enumerates every file and runs the real multipart-worker file separately with its required host registrant; those cases are not skipped. This is not hardware verification.
- Current native Kotlin compilation passed. Final APK construction and package/ABI/signature verification are recorded separately in `VERIFICATION.md`; an earlier native compile or the delivered 0.1.0 APK is not a substitute.
- The historical ledger retains original evidence and baseline gaps. `CURRENT_SCOPE_0.2.0.json` maps all 164 retained/adapted rows and 65 exclusions without claiming full original behavior or device parity. The three additional scope findings (share-app, Stretch dispatch, trusted-config recovery) have passing regressions.

## Implemented code is not device verification

- **Cast and temporary LAN sharing:** sender/session controls, explicit-action preparation, local-file serving, indexed offline HLS/DASH package resources and converted WebVTT have source/component coverage. Real receiver discovery, codec/manifest/subtitle support, seeking and route handoff still need Android/receiver tests. No server should start merely because a player opens or a connected receiver is observed.
- **Multipart downloads:** a narrowly patched, licensed copy of pinned `background_downloader` 9.6.5 preserves completed chunks on resume and fixes a desktop resume-record ordering race. Real Linux HTTP range workers have passed exact-byte/SHA-256 and saved-offset checks. Android WorkManager, OS termination and process-kill/restart recovery remain unverified. Disk JSON rehydration is not process-restart evidence. See `third_party/background_downloader/VENDORED.md` for provenance and the required test invocation.
- **Segmented downloads:** bounded static, non-DRM HLS/DASH packaging is implemented with validated indexed resources and redirect/access-denial tests. Synthetic package/hash fixtures are not real decoder or receiver playback tests. Unsupported DRM, live/dynamic and unbounded manifests are rejected rather than bypassed.
- **Background audio:** the native foreground service/media session bridges controls to the existing Flutter decoder; it is not a second decoder. Notification permissions, audio focus, lock-screen controls, OS background restrictions and interruption/recovery need device testing.
- **External players/downloaders and file reveal:** package-targeted intents and scoped local-file grants are implemented. Installed-app behavior, receiver compatibility and device storage-provider behavior remain unverified.
- **Embedded video:** the activity has navigation, fullscreen/file-chooser/download-confirmation code. Controlled GET/HEAD resource fetching has JVM/local-HTTP policy and streaming tests, including per-hop redirect checks, timeouts and access-denial passthrough. These do not prove Android WebView execution. Redirected HTML/CSS/module effective-base URL and CORS semantics remain unverified; `WebResourceResponse` does not expose a final-response URL field. POST/OPTIONS and authenticated embed flows are not supported by the restricted fetcher. No unchecked-network, unsafe-TLS or denial-bypass fallback is used.
- **Player/platform controls:** PiP, decoder tracks, brightness/volume, external subtitles, orientation and audio behavior need current-release device checks. Host widget tests and mocked method channels do not establish native execution.

## Deliberate limits and behavior

- Temporary sharing selects a private Wi-Fi/Ethernet IPv4 address. It does not fall back to a public/mobile/VPN address. Only registered files and validated package resources are exposed; closing a lease revokes sharing and removes only owned session temporaries, never completed user media.
- Download notification preferences are retained per original task. Changing the current preference does not retroactively silence every active native job, and Android can require a foreground-work notification.
- Pagination preserves raw upstream continuation even across locally filtered or duplicate-only pages. Automatic prefetch is bounded; the user can request further pages. A nonempty raw page is not proof that matching visible items exist.
- Top 250 labels preserve observed IMDb-ordered routes; they do not establish an independently verified ranking or exact count. The original animation category is not an anime-only classifier.
- Optional discovery accepts and caches only trusted HTTPS candidates after a schema check; cached values are validated before use. Failure retains the trusted configuration. Eligible read-only GET transport failures get one replay, not an unlimited recovery loop; HTTP errors/denials, bad certificates, cancellation and POSTs are not retried. The trust allowlist currently has one service host, not a fabricated collection of alternate domains. A completed discovery check alone is not proof of current connectivity.
- The live catalog smoke test is read-only and account-free. Retrieving a source URL is not a playback test, entitlement test or permission to redistribute media. Legacy external HTTP media/artwork remains a privacy/integrity tradeoff; catalog API destinations are separately restricted.
- Native automatic release lint and Java/resource shrinking are disabled for this constrained-host beta workflow. This is not a native lint pass. Dart release builds remain AOT; production release validation still requires the omitted checks.

## Intentionally excluded

Accounts, registration, subscriptions, billing/payments, posting/rating submissions, private server-side account lists, advertising, live channels, public playlists, original-vendor shop/support/community/news/Telegram/updater/version-download surfaces and the specified promotional brands are excluded by user direction. Private device-local collections, read-only film/series comments and episode playback queues remain in scope. Desktop-only helper binaries are not Android parity requirements.
