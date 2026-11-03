// Explicit opt-in live read-only probe, outside default test discovery.
// Only local preference storage is a fixture; API responses are real network data.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_smoke.dart' as probe;

// Use the normal Dart HTTP client instead of Flutter test's deliberate HTTP-400
// client. This does not change TLS validation, credentials or access denials.
class _LiveReadOnlyNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('live read-only catalog contracts and source availability', () async {
    // Explicit test-only harness outside automatic test discovery.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await HttpOverrides.runWithHttpOverrides(
      probe.main,
      _LiveReadOnlyNetwork(),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
