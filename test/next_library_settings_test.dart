import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/state/app_state.dart';

void main() {
  test(
    'platform fonts resolve generic families and preserve safe custom fonts',
    () {
      expect(
        AppSettings(subtitleFontFamily: 'serif').resolvedSubtitleFontFamily,
        isNot('serif'),
      );
      expect(
        AppSettings(subtitleFontFamily: 'monospace').resolvedSubtitleFontFamily,
        isNot('monospace'),
      );
      expect(
        AppSettings(subtitleFontFamily: 'My Font').resolvedSubtitleFontFamily,
        'My Font',
      );
      expect(AppSettings().subtitleFontFamilyFallback, isNotEmpty);
    },
  );
  test('new settings validate imports and roundtrip every field', () {
    final prefs = AppSettings().copyWith(
      subtitleEnabled: false,
      subtitleFontFamily: 'Custom Font',
      videoFit: 'cover',
      audioOnly: true,
      playerVolume: 0.42,
      rememberVolume: true,
      backgroundAudio: true,
      closeOnCompletion: true,
      resumeRewindSeconds: 120,
      parallelDownloads: 8,
      compactCatalog: true,
      introCompleted: true,
      externalPlayerPackage: 'org.videolan.vlc',
    );
    expect(AppSettings.fromJson(prefs.toJson()).toJson(), prefs.toJson());
    final invalid = AppSettings.fromJson({
      'playerVolume': -1,
      'parallelDownloads': 999,
      'resumeRewindSeconds': -4,
      'videoFit': 'bad',
      'subtitleEnabled': 1,
      'subtitleFontFamily': '\u0000bad',
      'externalPlayerPackage': 'https://bad.example',
      'introCompleted': false,
    });
    expect(invalid.playerVolume, 1);
    expect(invalid.parallelDownloads, 3);
    expect(invalid.resumeRewindSeconds, 5);
    expect(invalid.videoFit, 'contain');
    expect(invalid.subtitleEnabled, true);
    expect(invalid.subtitleFontFamily, 'sans-serif');
    expect(invalid.externalPlayerPackage, 'ask');
    expect(invalid.introCompleted, false);
  });
  test(
    'new settings expose next-release defaults, legacy JSON skips intro',
    () {
      final json = AppSettings().toJson();
      expect(json['subtitleEnabled'], true);
      expect(json['subtitleFontFamily'], 'sans-serif');
      expect(json['videoFit'], 'contain');
      expect(json['audioOnly'], false);
      expect(json['playerVolume'], 1.0);
      expect(json['rememberVolume'], false);
      expect(json['backgroundAudio'], false);
      expect(json['closeOnCompletion'], false);
      expect(json['resumeRewindSeconds'], 5);
      expect(json['parallelDownloads'], 3);
      expect(json['compactCatalog'], false);
      expect(json['introCompleted'], false);
      expect(json['externalPlayerPackage'], 'ask');
      expect(AppSettings.fromJson({}).toJson()['introCompleted'], true);
    },
  );
}
