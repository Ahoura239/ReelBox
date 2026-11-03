import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/content_policy.dart';
import 'local_media_server.dart';
import 'segmented_download.dart';
import 'subtitle_webvtt.dart';

/// Explicit resource ownership, also injectable into the native-session tests.
class CastMediaLease {
  CastMediaLease({required Map<String, dynamic> payload, this._onClose})
    : _payload = Map<String, dynamic>.unmodifiable(payload);
  final Map<String, dynamic> _payload;
  final Future<void> Function()? _onClose;
  Future<void>? _closing;
  Map<String, dynamic> get payload => _payload;
  Future<void> close() => _closing ??= Future<void>.sync(() async {
    await _onClose?.call();
  });
}

/// No filesystem or network side effects until an explicit Cast load.
class CastMediaShare {
  static Future<CastMediaLease> prepare({
    required Map<String, dynamic> payload,
    String? localFile,
    String? subtitleText,
    InternetAddress? bindAddress,
    String? advertisedHost,
  }) async {
    final result = Map<String, dynamic>.from(payload)..remove('subtitleUrl');
    File? selected;
    final extraFiles = <String, File>{};
    if (localFile != null) {
      if (!File(localFile).isAbsolute) {
        throw ArgumentError('Select an absolute media file.');
      }
      selected = File(await File(localFile).resolveSymbolicLinks());
      final stat = await selected.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        throw ArgumentError('Select an existing nonempty media file.');
      }
      if (RegExp(
        r'\.(m3u8|mpd)$',
        caseSensitive: false,
      ).hasMatch(selected.path)) {
        final directory = selected.parent;
        final index = File('${directory.path}/package.json');
        if (!await index.exists() || await index.length() > 16 * 1024 * 1024) {
          throw UnsupportedError('Select a complete indexed offline package.');
        }
        final id = directory.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        final downloads = SegmentedDownload(root: directory.parent);
        final package = await downloads.load(id);
        if (await File(package.path).resolveSymbolicLinks() != selected.path ||
            !await downloads.validate(id)) {
          throw StateError('Offline package is incomplete or damaged.');
        }
        for (final name in {
          ...package.manifests.keys,
          ...package.resources.map((resource) => resource.filename),
        }) {
          final file = File('${directory.path}/$name');
          final canonical = File(await file.resolveSymbolicLinks());
          if (canonical.parent.path != directory.path) {
            throw StateError('Offline resource leaves the selected package.');
          }
          // The selected root is already registered under media.<extension>.
          if (name != 'media.${selected.path.split('.').last.toLowerCase()}') {
            extraFiles[name] = file;
          }
        }
      } else if (!RegExp(
        r'\.(mp4|m4v|mkv|webm|mov|avi|mp3|aac)$',
        caseSensitive: false,
      ).hasMatch(selected.path)) {
        throw UnsupportedError(
          'This local media format requires an indexed offline package.',
        );
      }
      result['contentType'] = _mime(selected.path);
    } else {
      final url = result['url'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          !ContentPolicy.allowsUrl(url as String)) {
        throw ArgumentError('A permitted HTTP(S) media URL is required.');
      }
    }
    Directory? disposable;
    LocalMediaServer? server;
    try {
      File? subtitles;
      if (subtitleText != null) {
        if (utf8.encode(subtitleText).length > 8 * 1024 * 1024) {
          throw const FormatException('Subtitle exceeds 8 MB.');
        }
        final vtt = SubtitleWebVtt.convert(subtitleText);
        disposable = await Directory.systemTemp.createTemp('reelbox-cast-');
        subtitles = await File('${disposable.path}/selected.vtt')
            .writeAsString(vtt, encoding: utf8, flush: true);
      }
      if (selected == null && subtitles == null) {
        return CastMediaLease(payload: result);
      }
      final sharing = await LocalMediaServer.start(
        file: selected ?? subtitles!,
        subtitle: selected == null ? null : subtitles,
        bindAddress: bindAddress,
        advertisedHost: advertisedHost,
        extraFiles: extraFiles,
      );
      server = sharing;
      if (selected != null) result['url'] = sharing.mediaUri.toString();
      if (subtitles != null) {
        result['subtitleUrl'] =
            (selected == null ? sharing.mediaUri : sharing.subtitleUri!)
                .toString();
      }
      final owned = disposable;
      return CastMediaLease(
        payload: result,
        onClose: () async {
          try {
            await sharing.close();
          } finally {
            if (owned != null && await owned.exists()) {
              await owned.delete(recursive: true);
            }
          }
        },
      );
    } catch (_) {
      try {
        await server?.close();
      } finally {
        if (disposable != null && await disposable.exists()) {
          await disposable.delete(recursive: true);
        }
      }
      rethrow;
    }
  }

  static String _mime(String path) =>
      switch (path.split('.').last.toLowerCase()) {
        'webm' => 'video/webm',
        'mkv' => 'video/x-matroska',
        'mov' => 'video/quicktime',
        'avi' => 'video/x-msvideo',
        'mp3' => 'audio/mpeg',
        'aac' => 'audio/aac',
        'mpd' => 'application/dash+xml',
        'm3u8' => 'application/vnd.apple.mpegurl',
        _ => 'video/mp4',
      };
}
