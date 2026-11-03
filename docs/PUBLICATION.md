# Public-source preparation

## What changed from the delivered 0.2.0 source snapshot

- Moved the two service access constants out of version-controlled source into compile-time `String.fromEnvironment` configuration: `REELBOX_API_KEY` and `REELBOX_ACTOR_KEY`
- Updated affected API and discovery fixture assertions to verify supplied build configuration, rather than production literals; all legacy actor/theme/reply request sites reference the same configurable actor key
- Added the complete GNU GPL v3 text, build/configuration instructions, dependency license inventory, and the download website with deployment configuration
- Started a clean initial repository snapshot rather than publishing local development commits containing embedded service credentials

The signed 0.2.0 APK is unchanged: SHA-256 `2c224625b0492d04a3fb7ead1c71710e29d91f5ea6da0818846159e4407f15d0`. It was built before the two constants became configurable; a service-authorized private defines file supplies their equivalent values for future builds. The website's source archive is the sanitized, GPL-licensed public source, not the earlier private delivery archive.

## Verification of configurable source

The affected assertions were observed RED with the old embedded constants, then GREEN with the compile-time configuration. RED diagnostics stay private because matcher output contains portions of the old credentials.

After the change, the full host verifier passed again: **339 tests across all 49 test files** (336 ordinary plus 3 real-worker multipart tests), with clean analysis. See `verification-publication/verification.json` and its logs. No live service access is needed for this fixture-based run.

The opt-in live read-only smoke test also passed with a private defines file after this change; the local preference fixture was mocked, but remote API responses and normal TLS validation were not replaced.

Earlier build/live API/signature/device-limitation evidence is preserved in `VERIFICATION.md`. Publication is not a new Android hardware test or an independent post-fix review.

## Source hygiene

Private SSH keys, release-signing keys/passwords, local build paths/properties, private service configuration, APKs and compiler caches are not part of the Git repository. Third-party licenses remain intact. Production service key values are scanned for exact matches before publication. Credentials compiled into any client binary should not be treated as a durable security boundary.
