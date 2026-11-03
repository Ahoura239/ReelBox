import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_helpers.dart';
import 'package:reelbox/media/media_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('player handoff retains pre-player brightness rather than an earlier override', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MediaPlatform.channel, null);
    });
    var windowBrightness = -1.0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaPlatform.channel, (call) async {
          switch (call.method) {
            case 'getBrightness':
              return windowBrightness;
            case 'getEffectiveBrightness':
              return .55;
            case 'getVolume':
              return .5;
            case 'setBrightness':
              windowBrightness = (call.arguments as Map)['value'] as double;
              return null;
          }
          return null;
        });
    final old = PlaybackLifecycle(), current = PlaybackLifecycle();
    final oldControls = PlayerSystemControls(),
        currentControls = PlayerSystemControls();
    await old.setup([oldControls.capture]);
    await MediaPlatform.invoke<void>('setBrightness', {'value': .8});
    await current.setup([currentControls.capture]);
    expect(currentControls.brightness, .8);
    await old.dispose(oldControls.restore);
    expect(
      windowBrightness,
      .8,
      reason: 'Old teardown must not disturb the current owner',
    );
    await current.dispose(currentControls.restore);
    expect(
      windowBrightness,
      -1.0,
      reason: 'Last owner must restore the original activity baseline',
    );
  });
}
