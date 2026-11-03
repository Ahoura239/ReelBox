import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Explicit, short-lived private-LAN media sharing. The random session URL is a
/// bearer capability; never log/persist it. Only caller-registered files exist
/// in this HTTP namespace. No filesystem path is derived from a request.
class LocalMediaServer {
  LocalMediaServer._(
    this._server,
    this._host,
    this._token,
    this._files,
    this._mediaName,
    this._subtitleName,
  ) : _port = _server.port {
    _server.listen((request) {
      final operation = _handle(request);
      _pending.add(operation);
      unawaited(operation.whenComplete(() => _pending.remove(operation)));
    }, onError: (Object _) {});
  }

  final HttpServer _server;
  final String _host, _token, _mediaName;
  final String? _subtitleName;
  final int _port;
  final Map<String, _RegisteredMedia> _files;
  final Set<Future<void>> _pending = {};
  Future<void>? _closing;
  bool _closed = false;

  static Future<LocalMediaServer> start({
    required File file,
    File? subtitle,
    InternetAddress? bindAddress,
    String? advertisedHost,
    Map<String, File> extraFiles = const {},
  }) async {
    final address = bindAddress ?? await _discoverAddress();
    final hostAddress = InternetAddress.tryParse(
      advertisedHost ?? address.address,
    );
    if (hostAddress == null ||
        (!hostAddress.isLoopback && !_privateV4(hostAddress))) {
      throw ArgumentError(
        'Choose a private LAN address for local media sharing.',
      );
    }
    if (!address.isLoopback &&
        !_privateV4(address) &&
        address.address != '0.0.0.0') {
      throw ArgumentError(
        'Local media sharing cannot bind a public interface.',
      );
    }
    final mediaName = 'media${_extension(file)}';
    final subtitleName = subtitle == null
        ? null
        : 'subtitle${_extension(subtitle)}';
    final selected = <String, File>{mediaName: file};
    if (subtitleName != null && subtitle != null) {
      selected[subtitleName] = subtitle;
    }
    for (final entry in extraFiles.entries) {
      if (!_safeName(entry.key) || selected.containsKey(entry.key)) {
        throw ArgumentError('Invalid or reserved local resource name.');
      }
      selected[entry.key] = entry.value;
    }
    final registered = <String, _RegisteredMedia>{};
    for (final entry in selected.entries) {
      registered[entry.key] = await _RegisteredMedia.create(entry.value);
    }
    final random = Random.secure();
    final token = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final server = await HttpServer.bind(address, 0, shared: false);
    server.autoCompress = false;
    return LocalMediaServer._(
      server,
      hostAddress.address,
      token,
      registered,
      mediaName,
      subtitleName,
    );
  }

  static bool _safeName(String name) =>
      name.isNotEmpty &&
      name
          .split('/')
          .every(
            (part) =>
                part.isNotEmpty &&
                !part.startsWith('.') &&
                RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(part),
          );

  Uri _uri(String name) => Uri(
    scheme: 'http',
    host: _host,
    port: _port,
    pathSegments: [_token, ...name.split('/')],
  );
  Uri get mediaUri => _uri(_mediaName);
  Uri? get subtitleUri => _subtitleName == null ? null : _uri(_subtitleName);

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _server.close(force: true);
    await Future.wait(_pending.toList());
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final parts = request.uri.pathSegments;
      final name = parts.length > 1 ? parts.skip(1).join('/') : '';
      final resource =
          parts.isNotEmpty && parts.first == _token && _safeName(name)
          ? _files[name]
          : null;
      if (_closed || resource == null || !await resource.unchanged()) {
        response.statusCode = HttpStatus.notFound;
        response.contentLength = 0;
        await response.close();
        return;
      }
      response.headers.set('access-control-allow-origin', '*');
      response.headers.set(
        'access-control-allow-methods',
        'GET, HEAD, OPTIONS',
      );
      response.headers.set('access-control-allow-headers', 'Range, If-Range');
      response.headers.set(
        'access-control-expose-headers',
        'Content-Length, Content-Range, Accept-Ranges',
      );
      if (request.headers.value('access-control-request-private-network') ==
          'true') {
        response.headers.set('access-control-allow-private-network', 'true');
      }
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        response.contentLength = 0;
        await response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD, OPTIONS');
        response.contentLength = 0;
        await response.close();
        return;
      }
      final size = resource.stat.size;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        _contentType(resource.source),
      );
      response.headers.set(
        HttpHeaders.lastModifiedHeader,
        HttpDate.format(resource.stat.modified.toUtc()),
      );
      var start = 0, end = size - 1;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
        var valid =
            match != null &&
            size > 0 &&
            (match.group(1)!.isNotEmpty || match.group(2)!.isNotEmpty);
        if (valid) {
          if (match.group(1)!.isEmpty) {
            final suffix = int.tryParse(match.group(2)!);
            valid = suffix != null && suffix > 0;
            if (valid) start = max(0, size - suffix);
          } else {
            final first = int.tryParse(match.group(1)!);
            final last = match.group(2)!.isEmpty
                ? size - 1
                : int.tryParse(match.group(2)!);
            valid =
                first != null && last != null && first < size && last >= first;
            if (valid) {
              start = first;
              end = min(last, size - 1);
            }
          }
        }
        if (!valid) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
          response.contentLength = 0;
          await response.close();
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$size',
        );
      }
      response.contentLength = size == 0 ? 0 : end - start + 1;
      if (request.method == 'GET' && size > 0) {
        await response.addStream(
          File(resource.canonicalPath).openRead(start, end + 1),
        );
      }
      await response.close();
    } catch (_) {
      // Never expose filesystem paths or capability tokens to a disconnected peer.
      try {
        await response.close();
      } catch (_) {
        /* Socket already closed. */
      }
    }
  }

  static String _extension(File file) =>
      RegExp(r'\.[A-Za-z0-9]{1,8}$')
          .firstMatch(file.path)
          ?.group(0)
          ?.toLowerCase() ??
      '';
  static String _contentType(File file) => switch (_extension(file)) {
    '.mp4' || '.m4v' => 'video/mp4',
    '.mkv' => 'video/x-matroska',
    '.webm' => 'video/webm',
    '.m3u8' => 'application/vnd.apple.mpegurl',
    '.mpd' => 'application/dash+xml',
    '.ts' => 'video/mp2t',
    '.m4s' => 'video/iso.segment',
    '.aac' => 'audio/aac',
    '.mp3' => 'audio/mpeg',
    '.vtt' => 'text/vtt; charset=utf-8',
    '.srt' => 'text/plain; charset=utf-8',
    '.ttml' || '.xml' => 'application/ttml+xml',
    _ => 'application/octet-stream',
  };
  static bool _privateV4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final b = address.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }

  static Future<InternetAddress> _discoverAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      if (!RegExp(
        r'^(wlan|wifi|eth|en)',
        caseSensitive: false,
      ).hasMatch(interface.name)) {
        continue;
      }
      for (final address in interface.addresses) {
        if (_privateV4(address)) return address;
      }
    }
    throw StateError(
      'Connect to a private Wi-Fi or Ethernet network to share offline media.',
    );
  }
}

class _RegisteredMedia {
  const _RegisteredMedia(this.source, this.canonicalPath, this.stat);
  final File source;
  final String canonicalPath;
  final FileStat stat;
  static Future<_RegisteredMedia> create(File file) async {
    final source = file.absolute;
    try {
      final path = await source.resolveSymbolicLinks();
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) {
        throw ArgumentError('Select an existing media file.');
      }
      return _RegisteredMedia(source, path, stat);
    } on FileSystemException {
      throw ArgumentError('The selected media file is unavailable.');
    }
  }

  Future<bool> unchanged() async {
    try {
      if (await source.resolveSymbolicLinks() != canonicalPath) return false;
      final current = await File(canonicalPath).stat();
      return current.type == FileSystemEntityType.file &&
          current.size == stat.size &&
          current.modified == stat.modified;
    } on FileSystemException {
      return false;
    }
  }
}
