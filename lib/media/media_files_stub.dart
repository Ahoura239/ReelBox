Future<bool> exists(String path) async => false;
Future<int> size(String path) async => 0;
Future<void> delete(String path) async =>
    throw UnsupportedError('Native files are unavailable in the browser.');
Future<List<Map<String, dynamic>>> recoverPackages() async => [];
Future<Map<String, dynamic>> preparePackage({
  required String id,
  required String url,
  required String type,
  required Map<String, dynamic> metadata,
  required int parallel,
}) async => throw UnsupportedError('Offline packages require the Android app.');
Future<void> runPackage(
  String id,
  void Function(Map<String, dynamic>) onProgress,
) async => throw UnsupportedError('Offline packages require the Android app.');
Future<void> pausePackage(String id, {bool cancel = false}) async =>
    throw UnsupportedError('Offline packages require the Android app.');
Future<void> deletePackage(String id) async =>
    throw UnsupportedError('Offline packages require the Android app.');
Future<String> exportPackage(String id) async =>
    throw UnsupportedError('Offline packages require the Android app.');
Future<bool> validatePackage(String id) async => false;
Future<Map<String, dynamic>> loadPackage(String id) async =>
    throw UnsupportedError('Offline packages require the Android app.');
