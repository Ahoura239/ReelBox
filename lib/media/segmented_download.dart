import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';

import '../data/content_policy.dart';

import 'package:xml/xml.dart';

/// An owned resource, never a remote reference in a published manifest.
class OfflineResource {
  OfflineResource({
    required this.url,
    required this.filename,
    this.offset,
    this.length,
    this.key = false,
    this.bytes = 0,
    this.digest = '',
  });
  final String url, filename;
  final int? offset, length;
  final bool key;
  int bytes;
  String digest;
  factory OfflineResource.fromJson(Map<String, dynamic> j) => OfflineResource(
    url: j['url'] as String,
    filename: j['filename'] as String,
    offset: j['offset'] as int?,
    length: j['length'] as int?,
    key: j['key'] == true,
    bytes: j['bytes'] as int? ?? 0,
    digest: j['digest'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'url': url,
    'filename': filename,
    'offset': offset,
    'length': length,
    'key': key,
    'bytes': bytes,
    'digest': digest,
  };
}

class OfflinePackage {
  OfflinePackage({
    required this.id,
    required this.url,
    required this.directory,
    required this.manifest,
    required this.resources,
    required this.manifests,
    this.metadata = const {},
    this.status = 'paused',
    this.error = '',
  });
  final String id, url, directory, manifest;
  final List<OfflineResource> resources;
  final Map<String, String> manifests;
  final Map<String, dynamic> metadata;
  String status, error;
  int get receivedBytes => resources.fold(0, (n, r) => n + r.bytes);
  double get progress => resources.isEmpty
      ? 0
      : resources.where((r) => r.digest.isNotEmpty).length / resources.length;
  String get path => '$directory/$manifest';
  factory OfflinePackage.fromJson(Map<String, dynamic> j, String directory) =>
      OfflinePackage(
        id: j['id'] as String,
        url: j['url'] as String,
        directory: directory,
        manifest: j['manifest'] as String,
        resources: (j['resources'] as List)
            .map(
              (r) =>
                  OfflineResource.fromJson(Map<String, dynamic>.from(r as Map)),
            )
            .toList(),
        manifests: Map<String, String>.from(j['manifests'] as Map),
        metadata: Map<String, dynamic>.from(j['metadata'] as Map? ?? {}),
        status: j['status'] as String,
        error: j['error'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'url': url,
    'manifest': manifest,
    'resources': resources.map((r) => r.toJson()).toList(),
    'manifests': manifests,
    'metadata': metadata,
    'status': status,
    'error': error,
  };
}

class _Stopped implements Exception {}

/// Durable, bounded package orchestration. Runs only while Dart is alive:
/// interrupted work recovers paused, never as a false completed download.
/// Each completed resource has a length AND SHA-256 check before reuse.
class SegmentedDownload {
  SegmentedDownload({
    required this.root,
    int parallel = 3,
    this.transfer,
    this.cancelTransfers,
  }) : parallel = parallel.clamp(1, 8);
  final Directory root;
  int parallel;
  final Future<void> Function(OfflinePackage, OfflineResource, String)?
  transfer;
  final Future<void> Function(String)? cancelTransfers;
  final Map<String, HttpClient> _running = {};
  final Map<String, String> _stopped = {};
  final Map<String, Future<void>> _writes = {};
  static bool _safeName(String s) => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(s);
  Directory _directory(String id) {
    if (!_safeName(id)) throw ArgumentError('Invalid package id');
    return Directory('${root.path}/$id');
  }

  static Uri _remote(String value) {
    final uri = Uri.parse(value);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !ContentPolicy.allowsUrl(value)) {
      throw UnsupportedError(
        'Only authorized public HTTP(S) media is supported.',
      );
    }
    return uri;
  }

  Future<void> _save(OfflinePackage p) {
    final previous = _writes[p.id] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) async {
      final file = File('${p.directory}/package.json');
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(p.toJson()), flush: true);
      await tmp.rename(file.path);
    });
    _writes[p.id] = next;
    return next;
  }

  Future<OfflinePackage> load(String id) async {
    final dir = _directory(id);
    final p = OfflinePackage.fromJson(
      jsonDecode(await File('${dir.path}/package.json').readAsString())
          as Map<String, dynamic>,
      dir.path,
    );
    if (p.id != id ||
        p.resources.any((r) => !_local(r.filename)) ||
        p.manifests.keys.any((s) => !_local(s)) ||
        !p.manifests.containsKey(p.manifest)) {
      throw const FormatException('Invalid offline package index.');
    }
    return p;
  }

  static bool _local(String name) =>
      RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name) && !name.startsWith('.');
  Future<List<OfflinePackage>> recover() async {
    if (!await root.exists()) return [];
    final result = <OfflinePackage>[];
    await for (final dir in root.list(followLinks: false)) {
      if (dir is! Directory ||
          !_safeName(dir.uri.pathSegments.where((s) => s.isNotEmpty).last)) {
        continue;
      }
      try {
        final p = await load(
          dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
        );
        if (_running.containsKey(p.id)) {
          result.add(p);
          continue;
        }
        if (p.status == 'running' || p.status == 'enqueued') {
          p.status = 'paused';
          await _save(p);
        }
        if (p.status == 'complete' && !await validate(p.id)) {
          p.status = 'failed';
          p.error = 'Offline files are missing or damaged; retry to repair.';
          await _save(p);
        }
        result.add(p);
      } on FileSystemException {
        /* Unfinished planning is not a published package. */
      } on FormatException {
        /* Corrupt indices never become playable entries. */
      }
    }
    return result;
  }

  /// Own redirects so every request (including resources) passes the same policy.
  /// Return the effective URI: relative manifest references belong to its origin.
  Future<(Uri, HttpClientResponse)> _get(
    HttpClient client,
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    for (var redirects = 0; ; redirects++) {
      final request = await client.getUrl(_remote(uri.toString()));
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (!const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        return (uri, response);
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      // Cancel rather than consuming an unbounded redirect response body.
      await response.listen((_) {}).cancel();
      if (redirects >= 5) {
        throw const HttpException('Too many media redirects.');
      }
      if (location == null || location.trim().isEmpty) {
        throw const HttpException('Media redirect has no Location.');
      }
      uri = _remote(uri.resolve(location).toString());
    }
  }

  Future<(Uri, String)> _text(HttpClient client, Uri uri) async {
    final (effectiveUri, response) = await _get(client, uri);
    if (response.statusCode != 200) {
      throw HttpException('Manifest HTTP ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) {
        throw const FormatException('Manifest is too large.');
      }
    }
    return (effectiveUri, utf8.decode(bytes));
  }

  Future<OfflinePackage> prepare({
    required String id,
    required String url,
    String type = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    final uri = _remote(url);
    if (RegExp(
      r'drm|widevine|playready|fairplay|protected',
      caseSensitive: false,
    ).hasMatch(type)) {
      throw UnsupportedError('DRM/protected streams cannot be downloaded.');
    }
    final directory = _directory(id);
    if (await directory.exists()) throw StateError('Package already exists.');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    final resources = <OfflineResource>[];
    final manifests = <String, String>{};
    try {
      final (effectiveUri, text) = await _text(client, uri);
      final seen = <String, String>{};
      String resource(Uri url, {int? offset, int? length, bool key = false}) {
        _remote(url.toString());
        final identity = '$url:$offset:$length';
        final prior = resources.where(
          (r) => '${r.url}:${r.offset}:${r.length}' == identity,
        );
        if (prior.isNotEmpty) return prior.first.filename;
        if (resources.length >= 20000) {
          throw UnsupportedError('Too many offline resources.');
        }
        final extension = key
            ? 'key'
            : (RegExp(r'\.(ts|m4s|mp4|aac|vtt|webvtt)$')
                      .firstMatch(url.path)
                      ?.group(1) ??
                  'bin');
        final name = 'resource_${resources.length}.$extension';
        resources.add(
          OfflineResource(
            url: url.toString(),
            filename: name,
            offset: offset,
            length: length,
            key: key,
          ),
        );
        return name;
      }

      Future<String> playlist(Uri url, String content, int depth) async {
        if (depth > 4) {
          throw UnsupportedError('HLS playlist nesting is too deep.');
        }
        if (seen.containsKey(url.toString())) return seen[url.toString()]!;
        final name = 'playlist_${seen.length}.m3u8';
        seen[url.toString()] = name;
        final lines = const LineSplitter()
            .convert(content)
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isEmpty || lines.first != '#EXTM3U') {
          throw const FormatException('Invalid HLS playlist.');
        }
        final output = <String>['#EXTM3U'];
        if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF:'))) {
          final variants = <(String, String, int)>[];
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].startsWith('#EXT-X-STREAM-INF:')) {
              if (i + 1 >= lines.length || lines[i + 1].startsWith('#')) {
                throw const FormatException('Missing variant URI.');
              }
              final attrs = _attributes(lines[i]);
              variants.add((
                lines[i],
                lines[i + 1],
                int.tryParse(attrs['BANDWIDTH'] ?? '') ?? 0,
              ));
            }
            if (lines[i].startsWith('#EXT-X-SESSION-KEY:')) {
              throw UnsupportedError('HLS session keys are unsupported.');
            }
          }
          variants.sort((a, b) => b.$3.compareTo(a.$3));
          final variant = variants.first;
          final attrs = _attributes(variant.$1);
          for (final kind in ['AUDIO', 'SUBTITLES']) {
            final group = attrs[kind];
            if (group == null) continue;
            final choices = lines
                .where((l) => l.startsWith('#EXT-X-MEDIA:'))
                .where((l) {
                  final a = _attributes(l);
                  return a['TYPE'] == kind && a['GROUP-ID'] == group;
                })
                .toList();
            if (choices.isEmpty) {
              throw UnsupportedError('Missing HLS $kind rendition.');
            }
            final selected = choices.firstWhere(
              (l) => _attributes(l)['DEFAULT'] == 'YES',
              orElse: () => choices.first,
            );
            final a = _attributes(selected);
            if (a['URI'] != null) {
              final child = url.resolve(a['URI']!);
              final (effectiveChild, childText) = await _text(client, child);
              final local = await playlist(
                effectiveChild,
                childText,
                depth + 1,
              );
              output.add(_replaceAttribute(selected, 'URI', local));
            } else if (kind == 'AUDIO') {
              output.add(selected);
            } else {
              throw UnsupportedError('Missing subtitle rendition URI.');
            }
          }
          final child = url.resolve(variant.$2);
          final (effectiveChild, childText) = await _text(client, child);
          final local = await playlist(effectiveChild, childText, depth + 1);
          output.addAll([variant.$1, local]);
        } else {
          if (!lines.contains('#EXT-X-ENDLIST')) {
            throw UnsupportedError(
              'Live/unbounded HLS is not an offline download.',
            );
          }
          int? nextLength, nextOffset;
          var previousEnd = 0;
          String? previousUrl;
          var segments = 0;
          var encrypted = false, explicitIv = false;
          for (final line in lines.skip(1)) {
            if (line.startsWith('#EXT-X-BYTERANGE:')) {
              final parts = line.split(':').last.split('@');
              nextLength = int.tryParse(parts[0]);
              nextOffset = parts.length > 1 ? int.tryParse(parts[1]) : null;
              if (nextLength == null || nextLength <= 0) {
                throw const FormatException('Invalid HLS byte range.');
              }
            } else if (line.startsWith('#EXT-X-KEY:') ||
                line.startsWith('#EXT-X-MAP:')) {
              final a = _attributes(line);
              final key = line.startsWith('#EXT-X-KEY:');
              if (key && a['METHOD'] == 'NONE') {
                encrypted = false;
                explicitIv = false;
                output.add(line);
                continue;
              }
              if (!key && encrypted && !explicitIv) {
                throw UnsupportedError(
                  'Encrypted HLS init maps require an explicit IV.',
                );
              }
              if (key) {
                encrypted = true;
                explicitIv = a['IV'] != null;
                if (explicitIv &&
                    !RegExp(r'^0[xX][0-9a-fA-F]{32}$').hasMatch(a['IV']!)) {
                  throw UnsupportedError('Invalid AES-128 IV.');
                }
              }
              if (key &&
                  (a['METHOD'] != 'AES-128' ||
                      (a['KEYFORMAT'] != null &&
                          a['KEYFORMAT'] != 'identity'))) {
                throw UnsupportedError(
                  'DRM/protected HLS encryption is unsupported.',
                );
              }
              final ref = a['URI'];
              if (ref == null) {
                throw const FormatException('Missing HLS resource URI.');
              }
              int? length, offset;
              if (a['BYTERANGE'] != null) {
                final parts = a['BYTERANGE']!.split('@');
                length = int.tryParse(parts[0]);
                offset = parts.length == 2 ? int.tryParse(parts[1]) : null;
                if (length == null ||
                    length <= 0 ||
                    offset == null ||
                    offset < 0) {
                  throw UnsupportedError(
                    'Map byte range requires an explicit valid offset.',
                  );
                }
              }
              final local = resource(
                url.resolve(ref),
                offset: offset,
                length: length,
                key: key,
              );
              output.add(
                _replaceAttribute(
                  line,
                  'URI',
                  local,
                ).replaceAll(RegExp(r',?BYTERANGE="[^"]*"'), ''),
              );
            } else if (!line.startsWith('#')) {
              final resolved = url.resolve(line);
              final offset = nextLength == null
                  ? null
                  : nextOffset ??
                        (previousUrl == resolved.toString()
                            ? previousEnd
                            : throw const FormatException(
                                'Implicit range has no preceding resource.',
                              ));
              output.add(
                resource(resolved, offset: offset, length: nextLength),
              );
              if (nextLength != null) previousEnd = offset! + nextLength;
              previousUrl = resolved.toString();
              nextLength = null;
              nextOffset = null;
              segments++;
            } else {
              if (line.contains('URI=') ||
                  line.startsWith('#EXT-X-PART') ||
                  line.startsWith('#EXT-X-SKIP') ||
                  line.startsWith('#EXT-X-SESSION')) {
                throw UnsupportedError('Unsupported HLS resource extension.');
              }
              output.add(line);
            }
          }
          if (segments == 0 || nextLength != null) {
            throw const FormatException('Empty or incomplete media playlist.');
          }
        }
        manifests[name] = '${output.join('\n')}\n';
        return name;
      }

      final String manifest;
      if (text.trimLeft().startsWith('#EXTM3U')) {
        manifest = await playlist(effectiveUri, text, 0);
      } else {
        manifest = 'offline.mpd';
        manifests[manifest] = _dash(
          text,
          effectiveUri,
          (url, offset, length) =>
              resource(url, offset: offset, length: length),
        );
      }
      if (resources.isEmpty) {
        throw const FormatException('Empty offline package.');
      }
      await directory.create(recursive: true);
      final p = OfflinePackage(
        id: id,
        url: url,
        directory: directory.path,
        manifest: manifest,
        resources: resources,
        manifests: manifests,
        metadata: metadata,
      );
      await _save(p);
      return p;
    } finally {
      client.close(force: true);
    }
  }

  static String _dash(
    String text,
    Uri origin,
    String Function(Uri, int?, int?) resource,
  ) {
    if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
      throw UnsupportedError('External XML entities are unsupported.');
    }
    final document = XmlDocument.parse(text);
    final mpd = document.rootElement;
    if (mpd.name.local != 'MPD' ||
        (mpd.getAttribute('type') ?? 'static') != 'static') {
      throw UnsupportedError('Only static DASH is supported.');
    }
    final all = [mpd, ...mpd.descendantElements];
    for (final element in all) {
      if ([
            'ContentProtection',
            'SegmentBase',
            'Location',
            'UTCTiming',
            'EventStream',
            'SubRepresentation',
          ].contains(element.name.local) ||
          element.attributes.any(
            (a) =>
                a.name.local == 'href' ||
                a.name.local == 'availabilityTimeOffset',
          )) {
        throw UnsupportedError('DRM/protected or unsupported DASH addressing.');
      }
    }
    List<XmlElement> children(XmlElement e, String tag) =>
        e.childElements.where((x) => x.name.local == tag).toList();
    XmlElement? one(XmlElement e, String tag) {
      final found = children(e, tag);
      if (found.length > 1) {
        throw UnsupportedError('Multiple DASH $tag entries are unsupported.');
      }
      return found.isEmpty ? null : found.single;
    }

    Uri base(XmlElement element, Uri parent) {
      final node = one(element, 'BaseURL');
      return node == null
          ? parent
          : _remote(parent.resolve(node.innerText.trim()).toString());
    }

    double? seconds(String? value) {
      if (value == null) return null;
      final m = RegExp(
        r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
      ).firstMatch(value);
      if (m == null) throw UnsupportedError('Unsupported DASH duration.');
      return (double.tryParse(m[1] ?? '') ?? 0) * 86400 +
          (double.tryParse(m[2] ?? '') ?? 0) * 3600 +
          (double.tryParse(m[3] ?? '') ?? 0) * 60 +
          (double.tryParse(m[4] ?? '') ?? 0);
    }

    final periods = children(mpd, 'Period');
    if (periods.length != 1) {
      throw UnsupportedError('Exactly one finite DASH Period is supported.');
    }
    final period = periods.single;
    if ((seconds(period.getAttribute('start')) ?? 0) != 0) {
      throw UnsupportedError('Nonzero DASH Period start is unsupported.');
    }
    final duration =
        seconds(period.getAttribute('duration')) ??
        seconds(mpd.getAttribute('mediaPresentationDuration'));
    final periodBase = base(period, base(mpd, origin));
    final adaptations = children(period, 'AdaptationSet');
    if (adaptations.isEmpty) {
      throw const FormatException('DASH has no adaptations.');
    }
    for (final adaptation in adaptations) {
      final representations = children(adaptation, 'Representation');
      if (representations.isEmpty) {
        throw UnsupportedError('DASH representation is missing.');
      }
      representations.sort(
        (a, b) => (int.tryParse(b.getAttribute('bandwidth') ?? '') ?? 0)
            .compareTo(int.tryParse(a.getAttribute('bandwidth') ?? '') ?? 0),
      );
      final rep = representations.first;
      final repBase = base(rep, base(adaptation, periodBase));
      final chain = [mpd, period, adaptation, rep];
      final templateAttrs = <String, String>{};
      XmlElement? template, list, timeline;
      for (final scope in chain) {
        final t = one(scope, 'SegmentTemplate'), l = one(scope, 'SegmentList');
        if (t != null) {
          template = t;
          for (final a in t.attributes) {
            templateAttrs[a.name.local] = a.value;
          }
          timeline = one(t, 'SegmentTimeline') ?? timeline;
        }
        if (l != null) list = l;
      }
      if ((template == null) == (list == null)) {
        throw UnsupportedError(
          'DASH requires one supported SegmentTemplate or SegmentList.',
        );
      }
      final output = XmlElement(XmlName.parts('SegmentList'));
      int? integer(String? v) => v == null ? null : int.tryParse(v);
      int positive(String? v, int fallback) {
        final n = integer(v) ?? fallback;
        if (n <= 0) {
          throw const FormatException('Invalid DASH timescale/duration.');
        }
        return n;
      }

      String local(String ref, String? byteRange) {
        int? offset, length;
        if (byteRange != null) {
          final m = RegExp(r'^(\d+)-(\d+)$').firstMatch(byteRange);
          if (m == null) {
            throw const FormatException('Invalid DASH byte range.');
          }
          offset = int.parse(m[1]!);
          length = int.parse(m[2]!) - offset + 1;
          if (length <= 0) {
            throw const FormatException('Invalid DASH byte range.');
          }
        }
        return resource(repBase.resolve(ref), offset, length);
      }

      void initialization(String ref, String? range) {
        output.children.add(
          XmlElement(XmlName.parts('Initialization'), [
            XmlAttribute(XmlName.parts('sourceURL'), local(ref, range)),
          ]),
        );
      }

      void segment(String ref, String? range) {
        output.children.add(
          XmlElement(XmlName.parts('SegmentURL'), [
            XmlAttribute(XmlName.parts('media'), local(ref, range)),
          ]),
        );
      }

      if (list != null) {
        for (final a in list.attributes) {
          if (![
            'timescale',
            'duration',
            'startNumber',
            'presentationTimeOffset',
          ].contains(a.name.local)) {
            throw UnsupportedError('Unsupported DASH SegmentList attribute.');
          }
          output.attributes.add(a.copy());
        }
        final init = one(list, 'Initialization');
        if (init != null) {
          final ref = init.getAttribute('sourceURL');
          if (ref == null) {
            throw UnsupportedError(
              'DASH initialization without sourceURL is unsupported.',
            );
          }
          initialization(ref, init.getAttribute('range'));
        }
        final t = one(list, 'SegmentTimeline');
        if (t != null) output.children.add(t.copy());
        final segments = children(list, 'SegmentURL');
        if (segments.isEmpty) {
          throw const FormatException('DASH segment list is empty.');
        }
        for (final s in segments) {
          final ref = s.getAttribute('media');
          if (ref == null ||
              s.getAttribute('index') != null ||
              s.getAttribute('indexRange') != null) {
            throw UnsupportedError('Unsupported DASH segment indexing.');
          }
          segment(ref, s.getAttribute('mediaRange'));
        }
        if (t == null && list.getAttribute('duration') == null) {
          throw UnsupportedError('DASH list requires explicit timing.');
        }
      } else {
        if (templateAttrs.keys.any(
          (k) => ![
            'timescale',
            'duration',
            'startNumber',
            'presentationTimeOffset',
            'initialization',
            'media',
          ].contains(k),
        )) {
          throw UnsupportedError('Unsupported DASH template attributes.');
        }
        final timescale = positive(templateAttrs['timescale'], 1);
        final start = integer(templateAttrs['startNumber']) ?? 1;
        final pto = integer(templateAttrs['presentationTimeOffset']) ?? 0;
        if (start < 0 || pto < 0) {
          throw const FormatException('Invalid DASH template timing.');
        }
        output.setAttribute('timescale', '$timescale');
        output.setAttribute('startNumber', '$start');
        if (pto != 0) output.setAttribute('presentationTimeOffset', '$pto');
        String expand(String pattern, int number, int time) {
          const escaped = '__DASH_DOLLAR__';
          var value = pattern.replaceAll('\$\$', escaped);
          value = value.replaceAllMapped(
            RegExp(
              r'\$(RepresentationID|Bandwidth|Number|Time)(?:%0(\d+)d)?\$',
            ),
            (m) {
              final token = m[1]!;
              final replacement = switch (token) {
                'RepresentationID' => rep.getAttribute('id'),
                'Bandwidth' => rep.getAttribute('bandwidth'),
                'Number' => '$number',
                _ => '$time',
              };
              if (replacement == null) {
                throw UnsupportedError('Missing DASH $token.');
              }
              final width = int.tryParse(m[2] ?? '') ?? 0;
              if (width > 20) {
                throw UnsupportedError('DASH number formatting too wide.');
              }
              return replacement.padLeft(width, '0');
            },
          );
          if (value.contains('\$')) {
            throw UnsupportedError('Unsupported DASH template token.');
          }
          return value.replaceAll(escaped, '\$');
        }

        final init = templateAttrs['initialization'];
        if (init != null) initialization(expand(init, start, 0), null);
        final media = templateAttrs['media'];
        if (media == null) {
          throw const FormatException('DASH media template is missing.');
        }
        if (timeline != null) {
          var time = 0, number = start;
          final entries = children(timeline, 'S');
          if (entries.isEmpty) {
            throw const FormatException('Empty DASH timeline.');
          }
          for (final s in entries) {
            time = integer(s.getAttribute('t')) ?? time;
            final d = positive(s.getAttribute('d'), 0),
                r = integer(s.getAttribute('r')) ?? 0;
            if (time < 0 || r < 0 || r > 20000) {
              throw UnsupportedError(
                'Unbounded/negative DASH timeline repeat is unsupported.',
              );
            }
            for (var i = 0; i <= r; i++) {
              segment(expand(media, number++, time), null);
              time += d;
            }
          }
          output.children.add(timeline.copy());
        } else {
          final d = positive(templateAttrs['duration'], 0);
          if (duration == null || duration <= 0) {
            throw UnsupportedError(
              'DASH duration is required for finite templates.',
            );
          }
          final count = (duration * timescale / d).ceil();
          if (count > 20000) throw UnsupportedError('Too many DASH segments.');
          output.setAttribute('duration', '$d');
          for (var i = 0; i < count; i++) {
            segment(expand(media, start + i, pto + i * d), null);
          }
        }
      }
      // Keep representation codec metadata, but replace all remote addressing.
      for (final scope in [adaptation, rep]) {
        scope.children.removeWhere(
          (n) =>
              n is XmlElement &&
              [
                'SegmentTemplate',
                'SegmentList',
                'BaseURL',
              ].contains(n.name.local),
        );
      }
      for (final other in representations.skip(1)) {
        adaptation.children.remove(other);
      }
      rep.children.add(output);
    }
    for (final scope in [mpd, period]) {
      scope.children.removeWhere(
        (n) =>
            n is XmlElement &&
            [
              'SegmentTemplate',
              'SegmentList',
              'BaseURL',
            ].contains(n.name.local),
      );
    }
    // Never retain a fetch-capable extension/reference that we didn't package.
    for (final element in [mpd, ...mpd.descendantElements]) {
      if (element.name.local == 'BaseURL' ||
          element.attributes.any(
            (a) =>
                ['href', 'sourceURL', 'media'].contains(a.name.local) &&
                (a.value.contains('://') || a.value.startsWith('/')),
          )) {
        throw UnsupportedError('Unpackaged DASH reference.');
      }
    }
    return document.toXmlString();
  }

  static Map<String, String> _attributes(String line) {
    final attrs = <String, String>{};
    for (final match in RegExp(
      r'([A-Z0-9-]+)=("[^"]*"|[^,]*)',
    ).allMatches(line.substring(line.indexOf(':') + 1))) {
      final value = match[2]!;
      attrs[match[1]!] = value.startsWith('"')
          ? value.substring(1, value.length - 1)
          : value;
    }
    return attrs;
  }

  static String _replaceAttribute(String line, String key, String value) =>
      line.replaceFirst(RegExp('$key=("[^"]*"|[^,]*)'), '$key="$value"');
  Future<bool> _validResource(OfflinePackage p, OfflineResource r) async {
    if (r.bytes <= 0 || r.digest.isEmpty) return false;
    final f = File('${p.directory}/${r.filename}');
    if (!await f.exists() || await f.length() != r.bytes) return false;
    return (await sha256.bind(f.openRead()).first).toString() == r.digest;
  }

  Future<bool> validate(String id) async {
    final p = await load(id);
    if (p.status != 'complete' || p.resources.isEmpty) return false;
    for (final r in p.resources) {
      if (!await _validResource(p, r)) return false;
    }
    for (final entry in p.manifests.entries) {
      final f = File('${p.directory}/${entry.key}');
      if (!await f.exists() || await f.readAsString() != entry.value) {
        return false;
      }
    }
    return true;
  }

  Future<OfflinePackage> run(
    String id, {
    void Function(OfflinePackage)? onProgress,
  }) async {
    if (_running.containsKey(id)) {
      throw StateError('Package is already running.');
    }
    final p = await load(id);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    _running[id] = client;
    _stopped.remove(id);
    p.status = 'running';
    p.error = '';
    await _save(p);
    onProgress?.call(p);
    Object? failure;
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < p.resources.length &&
          failure == null &&
          !_stopped.containsKey(id)) {
        final r = p.resources[cursor++];
        try {
          if (await _validResource(p, r)) {
            onProgress?.call(p);
            continue;
          }
          r.bytes = 0;
          r.digest = '';
          final tmp = File('${p.directory}/${r.filename}.part');
          if (transfer != null) {
            await transfer!(p, r, tmp.path);
          } else {
            final (_, response) = await _get(
              client,
              _remote(r.url),
              headers: {
                HttpHeaders.acceptEncodingHeader: 'identity',
                if (r.offset != null)
                  HttpHeaders.rangeHeader:
                      'bytes=${r.offset}-${r.offset! + r.length! - 1}',
              },
            );
            if (r.offset == null && response.statusCode != 200 ||
                r.offset != null && response.statusCode != 206) {
              throw HttpException(
                'Resource HTTP ${response.statusCode}; range authorization is required.',
              );
            }
            if (r.offset != null) {
              final range = response.headers.value('content-range') ?? '';
              if (!RegExp(
                '^bytes ${r.offset}-${r.offset! + r.length! - 1}/[0-9]+\$',
              ).hasMatch(range)) {
                throw const FormatException('Incorrect Content-Range.');
              }
            }
            final sink = tmp.openWrite();
            var count = 0;
            try {
              await for (final chunk in response.timeout(
                const Duration(seconds: 30),
              )) {
                if (_stopped.containsKey(id)) throw _Stopped();
                count += chunk.length;
                if (r.length != null && count > r.length!) {
                  throw const FormatException('Oversized range.');
                }
                sink.add(chunk);
              }
            } finally {
              await sink.close();
            }
            if (count == 0 ||
                r.length != null && count != r.length ||
                response.contentLength >= 0 &&
                    response.contentLength != count ||
                r.key && count != 16) {
              throw const FormatException(
                'Truncated/invalid offline resource.',
              );
            }
          }
          final count = await tmp.length();
          if (count == 0 ||
              r.length != null && count != r.length ||
              r.key && count != 16) {
            throw const FormatException('Invalid native resource length.');
          }
          if (_stopped.containsKey(id)) throw _Stopped();
          final digest = (await sha256.bind(tmp.openRead()).first).toString();
          await tmp.rename('${p.directory}/${r.filename}');
          r.bytes = count;
          r.digest = digest;
          await _save(p);
          onProgress?.call(p);
        } catch (e) {
          if (!_stopped.containsKey(id)) failure ??= e;
        }
      }
    }

    try {
      await Future.wait(List.generate(parallel, (_) => worker()));
      if (_stopped.containsKey(id)) {
        p.status = _stopped[id]!;
      } else if (failure != null) {
        p.status = 'failed';
        p.error = 'Offline resource failed: $failure';
      } else {
        for (final r in p.resources) {
          if (!await _validResource(p, r)) {
            throw StateError('Resource integrity check failed.');
          }
        }
        for (final entry in p.manifests.entries) {
          await File('${p.directory}/${entry.key}')
              .writeAsString(entry.value, flush: true);
        }
        p.status = 'complete';
      }
    } catch (e) {
      p.status = 'failed';
      p.error = e.toString();
    } finally {
      client.close(force: true);
      _running.remove(id);
      await _save(p);
      onProgress?.call(p);
    }
    return p;
  }

  Future<void> stop(String id, {bool cancel = false}) async {
    _stopped[id] = cancel ? 'canceled' : 'paused';
    final client = _running[id];
    client?.close(force: true);
    if (cancelTransfers != null) await cancelTransfers!(id);
    if (client == null) {
      final p = await load(id);
      p.status = _stopped[id]!;
      await _save(p);
    } else {
      while (_running.containsKey(id)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await _writes[id];
    }
  }

  final _exporting = <String>{};
  Future<String> export(String id) async {
    if (!_exporting.add(id)) {
      throw StateError('This package is already being exported.');
    }
    try {
      if (!await validate(id)) {
        throw StateError('Only a complete validated package can be exported.');
      }
      final p = await load(id);
      final dir = await Directory('${root.path}/exports')
          .create(recursive: true);
      final tmp = '${dir.path}/$id.zip.part';
      final encoder = ZipFileEncoder()
        ..create(tmp, level: ZipFileEncoder.store);
      try {
        // Deliberately omit package.json: it contains original remote URL metadata.
        for (final name in {
          ...p.manifests.keys,
          ...p.resources.map((r) => r.filename),
        }) {
          await encoder.addFile(File('${p.directory}/$name'), name);
        }
      } finally {
        await encoder.close();
      }
      final path = '${dir.path}/$id.zip';
      await File(tmp).rename(path);
      return path;
    } finally {
      _exporting.remove(id);
    }
  }

  Future<void> delete(String id) async {
    if (_running.containsKey(id)) await stop(id, cancel: true);
    await _directory(id).delete(recursive: true);
  }
}
