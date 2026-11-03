/// Converts already-decoded SRT, SSA/ASS or WebVTT text to plain-cue WebVTT.
/// Deliberately drops styling, attachments, identifiers and positioning rather
/// than allowing receiver-side fetches or pretending to preserve ASS rendering.
class SubtitleWebVtt {
  static String convert(String source) {
    final text = source
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    final cues = <_Cue>[];
    if (RegExp(r'^\[Script Info\]', caseSensitive: false).hasMatch(text)) {
      _ass(text, cues);
    } else {
      final blocks = text.split(RegExp(r'\n[ \t]*\n'));
      final vtt = RegExp(r'^WEBVTT(?:[ \t]|$)')
          .hasMatch(blocks.first.split('\n').first);
      if (vtt) blocks.removeAt(0); // Header metadata is never propagated.
      for (final block in blocks) {
        final lines = block.trim().split('\n');
        if (vtt &&
            RegExp(r'^(?:STYLE|REGION|NOTE)(?:[ \t]|$)')
                .hasMatch(lines.first)) {
          continue;
        }
        if (lines.length > 1 && !lines.first.contains('-->')) {
          if (!vtt && !RegExp(r'^\d+$').hasMatch(lines.first)) {
            throw const FormatException(
              'Unsupported subtitle format; use SRT, SSA/ASS or WebVTT.',
            );
          }
          lines.removeAt(0);
        }
        if (lines.length < 2) {
          throw const FormatException('Invalid or empty subtitle cue.');
        }
        final timing = RegExp(r'^(\S+)[ \t]+-->[ \t]+(\S+)(?:[ \t]+.*)?$')
            .firstMatch(lines.first);
        if (timing == null) {
          throw const FormatException(
            'Unsupported subtitle format; use SRT, SSA/ASS or WebVTT.',
          );
        }
        cues.add(
          _Cue(
            _time(timing[1]!, short: vtt),
            _time(timing[2]!, short: vtt),
            _plain(lines.skip(1).join('\n')),
          ),
        );
      }
    }
    if (cues.isEmpty) {
      throw const FormatException('No supported subtitle cues.');
    }
    var previous = -1;
    for (final cue in cues) {
      if (cue.end <= cue.start || cue.start < previous || cue.body.isEmpty) {
        throw const FormatException(
          'Invalid subtitle cue timing/order or empty text.',
        );
      }
      previous = cue.start;
    }
    return 'WEBVTT\n\n${cues.map((c) => '${_stamp(c.start)} --> ${_stamp(c.end)}\n${c.body}').join('\n\n')}\n\n';
  }

  static int _time(String value, {bool short = false, bool ass = false}) {
    final expression = ass
        ? r'^(\d{1,6}):(\d{2}):(\d{2})\.(\d{2})$'
        : r'^(\d{2,6}):(\d{2}):(\d{2})[.,](\d{3})$';
    var match = RegExp(expression).firstMatch(value);
    if (match == null && short) {
      match = RegExp(r'^(\d{2}):(\d{2})\.(\d{3})$').firstMatch(value);
      if (match != null) {
        return _time('00:$value');
      }
    }
    if (match == null) {
      throw const FormatException('Invalid subtitle timestamp.');
    }
    final h = int.parse(match[1]!);
    final m = int.parse(match[2]!);
    final s = int.parse(match[3]!);
    if (m > 59 || s > 59) {
      throw const FormatException('Invalid subtitle timestamp range.');
    }
    return ((h * 60 + m) * 60 + s) * 1000 +
        int.parse(match[4]!) * (ass ? 10 : 1);
  }

  static String _stamp(int ms) {
    String pad(int value, int width) => '$value'.padLeft(width, '0');
    return '${pad(ms ~/ 3600000, 2)}:${pad(ms ~/ 60000 % 60, 2)}:${pad(ms ~/ 1000 % 60, 2)}.${pad(ms % 1000, 3)}';
  }

  static void _ass(String text, List<_Cue> cues) {
    var events = false;
    List<String>? fields;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        events = line.toLowerCase() == '[events]';
        continue;
      }
      if (!events) continue;
      if (line.toLowerCase().startsWith('format:')) {
        fields = line
            .substring(line.indexOf(':') + 1)
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .toList();
      } else if (line.toLowerCase().startsWith('dialogue:')) {
        if (fields == null ||
            fields.last != 'text' ||
            !fields.contains('start') ||
            !fields.contains('end') ||
            fields.toSet().length != fields.length) {
          throw const FormatException('Invalid SSA/ASS Events format.');
        }
        final parts = line.substring(line.indexOf(':') + 1).split(',');
        if (parts.length < fields.length) {
          throw const FormatException('Incomplete SSA/ASS dialogue.');
        }
        final body = parts.skip(fields.length - 1).join(',');
        if (RegExp(r'\\p[1-9]').hasMatch(body)) {
          throw UnsupportedError('ASS drawing subtitles are not supported.');
        }
        cues.add(
          _Cue(
            _time(parts[fields.indexOf('start')].trim(), ass: true),
            _time(parts[fields.indexOf('end')].trim(), ass: true),
            _plain(
              body
                  .replaceAll(r'\N', '\n')
                  .replaceAll(r'\n', '\n')
                  .replaceAll(r'\h', ' '),
            ),
          ),
        );
      }
    }
  }

  static String _plain(String body) {
    // Plain escaped text is a strict subset of WebVTT: no HTML resources,
    // CSS, voice/class attributes, ASS overrides, or embedded timing tags.
    return body
        .replaceAll(
          RegExp(
            r'<(script|style)\b[^>]*>.*?</\1\s*>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(RegExp(r'<[^>]*>', dotAll: true), '')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .trim();
  }
}

class _Cue {
  const _Cue(this.start, this.end, this.body);
  final int start, end;
  final String body;
}
