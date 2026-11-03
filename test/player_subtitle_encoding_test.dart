import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_helpers.dart';

void main() {
  test('decodes real Windows-1256 Persian SRT fixture without replacement', () {
    final bytes = File('test/fixtures/player_persian_cp1256.srt').readAsBytesSync();
    final text = decodeSubtitle(bytes);
    expect(text, contains('سلام دنيا؛ پخش گچ پژ'));
    expect(text, contains('00:00:01,000 --> 00:00:03,000'));
    expect(text, isNot(contains('\uFFFD')));
  });
  test('UTF8 BOM and UTF16LE preserve subtitle text', () {
    expect(decodeSubtitle([239,187,191,...utf8.encode('سلام')]), 'سلام');
    expect(decodeSubtitle([255,254,0x33,0x06,0x44,0x06,0x27,0x06,0x45,0x06]), 'سلام');
  });
}
