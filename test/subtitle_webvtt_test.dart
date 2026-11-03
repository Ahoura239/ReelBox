import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/subtitle_webvtt.dart';

void main() {
  test('WebVTT drops metadata, STYLE, REGION, NOTE, cue settings and unsafe markup', () {
    final output = SubtitleWebVtt.convert('''WEBVTT synthetic header
X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0

STYLE
::cue { background-image: url(https://unsafe.invalid/pixel) }

REGION
id:remote

NOTE private note
https://unsafe.invalid/note

cue-id
00:01.250 --> 00:03.000 region:remote align:start
<b>سلام</b> <img src="https://unsafe.invalid/pixel"><script>bad()</script><style>bad-style</style> &amp; safe
''');
    expect(
      output,
      'WEBVTT\n\n00:00:01.250 --> 00:00:03.000\nسلام  &amp; safe\n\n',
    );
    expect(output, isNot(contains('unsafe.invalid')));
  });
  test('SRT cue payload is sanitized, not simply relabelled', () {
    expect(
      SubtitleWebVtt.convert(
        '1\n00:00:00,000 --> 00:00:01,500\n<i>Hello</i> {\\\\an8}<a href="https://unsafe.invalid">friend</a>',
      ),
      'WEBVTT\n\n00:00:00.000 --> 00:00:01.500\nHello friend\n\n',
    );
  });
  for (final timing in [
    '00:61:00,000 --> 01:02:00,000',
    '00:00:61,000 --> 00:02:00,000',
    '00:00:03,000 --> 00:00:01,000',
    '00:00:01,000 --> 00:00:01,000',
    '-00:00:01,000 --> 00:00:02,000',
  ]) {
    test('rejects invalid cue timing $timing', () {
      expect(
        () => SubtitleWebVtt.convert('1\n$timing\nSynthetic'),
        throwsFormatException,
      );
    });
  }
  test('rejects decreasing cue starts but permits overlapping cues', () {
    expect(
      () => SubtitleWebVtt.convert(
        '1\n00:00:02,000 --> 00:00:04,000\na\n\n2\n00:00:01,000 --> 00:00:03,000\nb',
      ),
      throwsFormatException,
    );
    expect(
      SubtitleWebVtt.convert(
        '1\n00:00:01,000 --> 00:00:04,000\na\n\n2\n00:00:02,000 --> 00:00:03,000\nb',
      ),
      contains('00:00:02.000 --> 00:00:03.000'),
    );
  });
  for (final unsupported in [
    '',
    '<tt><body>TTML is not supported</body></tt>',
    'plain arbitrary text',
    'WEBVTT\n\nSTYLE\n::cue {color:red}',
  ]) {
    test('rejects empty/unsupported input honestly: $unsupported', () {
      expect(() => SubtitleWebVtt.convert(unsupported), throwsFormatException);
    });
  }
  test('rejects invalid ASS time and drawing-mode dialogue', () {
    for (final body in [
      'Dialogue: 0,0:99:01.00,0:99:02.00,text',
      r'Dialogue: 0,0:00:01.00,0:00:02.00,{\p1}m 1 1 l 2 2',
    ]) {
      expect(
        () => SubtitleWebVtt.convert(
          '[Script Info]\n[Events]\nFormat: Layer, Start, End, Text\n$body',
        ),
        throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
      );
    }
  });
  for (final format in ['ASS', 'SSA']) {
    test('synthetic $format uses Events format and dialogue, never styles/fonts', () {
      final fields = format == 'ASS'
          ? 'Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text'
          : 'Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text';
      final output = SubtitleWebVtt.convert('''[Script Info]
Title: Synthetic only
[V4+ Styles]
Format: Name, Fontname
Style: Default,https://unsafe.invalid/font
[Events]
Format: $fields
Dialogue: 0,0:00:01.25,0:00:03.00,Default,,0,0,0,,{\\b1}سلام\\Nworld, again{\\b0}
''');
      expect(
        output,
        'WEBVTT\n\n00:00:01.250 --> 00:00:03.000\nسلام\nworld, again\n\n',
      );
      expect(output, isNot(contains('unsafe.invalid')));
    });
  }
  test('synthetic SRT becomes actual WebVTT while preserving Persian text', () {
    expect(
      SubtitleWebVtt.convert(
        '\ufeff1\r\n00:00:01,250 --> 00:00:03,000\r\nسلام دنیا\r\n',
      ),
      'WEBVTT\n\n00:00:01.250 --> 00:00:03.000\nسلام دنیا\n\n',
    );
  });
}
