import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'data/api_service.dart';
import 'media/download_service.dart';
import 'state/app_state.dart';
export 'app.dart' show MyApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(api: ApiService());
  runApp(
    ReelboxBootstrap(
      initialize: () async {
        // Native engine failure is recoverable too, not outside the startup guard.
        MediaKit.ensureInitialized();
        await state.initialize(discover: false);
        unawaited(
          state.api.initialize().catchError((Object _) {
            debugPrint(
              'Server discovery unavailable; keeping the trusted API base.',
            );
          }),
        );
        if (!kIsWeb) {
          DownloadService.instance.bindSettings(state);
          unawaited(
            DownloadService.instance.initialize().catchError((Object _) {
              debugPrint('Background downloader initialization unavailable.');
            }),
          );
        }
      },
      builder: (_) => MyApp(state: state),
    ),
  );
}
