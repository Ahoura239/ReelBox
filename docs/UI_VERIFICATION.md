# UI verification evidence

The four PNGs in `docs/ui/` are actual Flutter **host-rendered widget captures**, not mockups and not Android device screenshots. They exercise a 390 × 844 logical-pixel view and are saved at 2× resolution.

- `library-en.png`: empty local watchlist, library tabs and bottom navigation.
- `more-en.png`: account-free settings/directories/local-data actions.
- `settings-en.png`: mobile settings, dropdown selections and switches.
- `settings-fa.png`: Persian labels and right-to-left placement of controls.

The captured screens were visually inspected. The local-library and settings text, icons and RTL controls were readable without visible clipping at this view size. A capture-harness mismatch between surface and device metrics was corrected before retaining this evidence. The app-bar font family was also made explicit after the capture exposed missing test-font glyphs.

The harness uses an explicit empty public-catalog test adapter so that these local-data screens have deterministic first-use state; it does not represent a live populated catalog or successful playback. Host-installed font files are loaded only by the capture tool. These captures do not verify Android system bars/insets, native keyboard, font fallback on a physical phone, video decoding, PiP, downloads or notification behavior.

To reproduce on a Linux host:

```sh
export REELBOX_TEST_FONT=/path/to/DejaVuSans.ttf
export REELBOX_ICON_FONT=/path/to/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf
flutter test --concurrency=1 tool/ui_capture_test.dart
```

Optional: set `REELBOX_SCREENSHOT_DIR` for the output directory. The default output directory is `build/ui-verification`. The capture test checks the widget tree for Flutter exceptions, but visual inspection is a separate step.
