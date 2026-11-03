# Android user acceptance and revised release scope

## Evidence already received

The user reports: “The APK works on android and I'm able to play videos so that's checked off (and the other functionalities I tested worked too)”.

This records successful **user-reported Android installation/use and video playback** for the delivered 0.1.0 beta. The phone model, Android version, codecs, sources and other exact scenarios were not provided. Do not infer that Cast, background services, download restart, every subtitle format or every other native path was tested. This is valuable real-device user evidence, separate from developer-executed tests and host UI captures.

## Revised next-release requirements

- Keep film/series/anime discovery, details, recommendations, playback, subtitles, movie comments, device-local collections/history/settings and downloads.
- Implement remaining applicable Android and platform-independent functionality. Functional equivalents are the target; copying the original desktop helper processes or vendor identity is not.
- Remove live channels, their favorites/comments/share/filter routes, and all public/server playlists. Keep **private device-local collections** and **episode playback order**; those are different features.
- Never show/fetch an original-app installer/version/update feed or offer original APK downloads. Server API-domain discovery is infrastructure, not an app-update feed, and remains separately trust-restricted.
- Block the two named vendor promotions (including Persian/Arabic letter, diacritic, spacing and zero-width variants), original support/community links, Telegram destinations/accounts and associated news.
- Apply filtering at API decoding, model/import/local-library boundaries, shared rendering/navigation, and native external/web destinations so removed material cannot reappear via a different route.
- Do not automatically delete completed user video files merely because an old record belongs to a removed category. Hide the removed content and keep explicit safe storage-management behavior.
- Do not add accounts, registration, subscriptions, billing, private server mutations, advertising SDKs, vendor shop/support/community pages or an original-service updater.
- Generic legitimate embedded-video handling remains in scope, without the removed shop/vendor destinations.

## Integration and delivery acceptance

The next APK must preserve the existing application ID/signing identity so it can update the installed beta. Record every implementation and real executed check, reconcile the feature ledger, run full analysis/tests and an actual native ARM64 release build, then verify signature/manifest/ABI/archive and deliver updated source and coverage notes. Real Cast receivers and newly implemented Android service paths still need their own device verification; the earlier playback confirmation does not establish those.
