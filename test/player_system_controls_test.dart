import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaPlatform.channel, null);
  });
  test('player reads native control values and restores original window brightness', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final writes = <double>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaPlatform.channel, (call) async {
          switch (call.method) {
            case 'getBrightness':
              return -1.0;
            case 'getEffectiveBrightness':
              return .65;
            case 'getVolume':
              return .22;
            case 'setBrightness':
              writes.add((call.arguments as Map)['value'] as double);
              return null;
          }
          return null;
        });
    final controls = PlayerSystemControls();
    await controls.capture();
    expect(controls.brightness, .65);
    expect(controls.volume, .22);
    await controls.restore();
    expect(writes, [-1.0]);
  });
  test(
    'leaving a player that never initialized does not change brightness',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MediaPlatform.channel, (call) async {
            called = true;
            return null;
          });
      await PlayerSystemControls().restore();
      expect(called, isFalse);
    },
  );
}
