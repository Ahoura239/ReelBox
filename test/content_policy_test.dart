import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/content_policy.dart';

void main() {
  group('removed service promotions cannot reach the interface', () {
    for (final value in <String>[
      'ملودی باکس',
      'ملودي باكس',
      'مِلودی‌ باکس',
      'MELODY BOX',
      'MelodyBox music',
      'نورتون',
      'نُورتون',
      'Norton VPN',
      'دانلود نسخه جدید برنامه',
      'آپدیت برنامه سیمبا',
      'Original app support: https://t.me/original_support',
      'خبرهای سرویس در تلگرام',
      '@OriginalSupportAccount',
    ]) {
      test('blocks $value', () {
        expect(ContentPolicy.allowsText(value), isFalse);
        expect(ContentPolicy.sanitizeText(value), isEmpty);
      });
    }
    test('retains normal film metadata and does not mutate the input', () {
      final original = <String, dynamic>{
        'id': 5,
        'title': 'The Newsroom',
        'description': 'A story about a newspaper',
        'updated_at': '2026-10-01',
        'sources': [
          {'url': 'https://media.example/film.mp4', 'quality': '1080p'},
        ],
      };
      expect(ContentPolicy.allowsTitleJson(original), isTrue);
      expect(ContentPolicy.sanitizeJson(original), original);
      expect(original['updated_at'], '2026-10-01');
    });
    test('removes complete promotion records, not merely their labels', () {
      final clean = ContentPolicy.sanitizeJson({
        'posters': [
          {'id': 1, 'title': 'Ordinary film', 'type': 'movie'},
          {'id': 2, 'title': 'ملودی باکس', 'type': 'movie'},
          {
            'id': 3,
            'title': 'Install the latest app',
            'url': 'https://cdn.example/app.apk',
          },
          {'id': 4, 'title': 'Live station', 'type': 'channel'},
        ],
      }) as Map<String, dynamic>;
      expect((clean['posters'] as List).map((e) => e['id']), [1]);
    });
    test(
      'discards original support/news/update/list/channel home payloads',
      () {
        final clean = ContentPolicy.sanitizeJson({
          'posters': [
            {'id': 1, 'title': 'Film'},
          ],
          'channels': [
            {'id': 4, 'title': 'Station'},
          ],
          'public_playlists': [
            {'id': 2, 'title': 'Remote list'},
          ],
          'news': {'title': 'Latest news'},
          'support': 'https://example.com/support',
          'update': {'version': '99', 'url': 'https://example.com/new.apk'},
          'telegram_channel': '@OriginalAccount',
        }) as Map<String, dynamic>;
        expect(clean.keys, ['posters']);
      },
    );
    test('preserves local collections and episode playback playlists', () {
      final value = {
        'collections': [
          {'name': 'Weekend films', 'titles': []},
        ],
        'episodes': [
          {'id': 3, 'title': 'Episode 3'},
        ],
      };
      expect(ContentPolicy.sanitizeJson(value), value);
    });
    test('rejects channel and promotional records', () {
      expect(
        ContentPolicy.allowsTitleJson({
          'id': 4,
          'title': 'Station',
          'type': 'channel',
        }),
        isFalse,
      );
      expect(
        ContentPolicy.allowsTitleJson({
          'id': 5,
          'title': 'Movie',
          'description': 'نورتون',
        }),
        isFalse,
      );
      expect(
        ContentPolicy.allowsTitleJson({
          'id': 6,
          'title': 'Movie',
          'type': 'news',
        }),
        isFalse,
      );
    });
  });
  group('outgoing destination policy', () {
    for (final url in [
      'https://t.me/original',
      'https://www.telegram.me/original',
      'tg://resolve?domain=original',
      'https://telegram.org/original',
      'https://cdn.example/release.apk?version=2',
      'https://cdn.example/release%2Eapk',
      'https://example.com/original-app/support',
      'https://www.norton.com/',
      'https://melodybox.example/',
      'javascript:alert(1)',
      'intent://example',
    ]) {
      test('rejects $url', () => expect(ContentPolicy.allowsUrl(url), isFalse));
    }
    test('allows normal artwork, film and subtitle media URLs', () {
      for (final url in [
        'https://media.example/film.mp4',
        'http://media.example/video.m3u8',
        'https://images.example/p.jpg',
        'https://subtitles.example/fa.srt',
      ]) {
        expect(ContentPolicy.allowsUrl(url), isTrue, reason: url);
      }
    });
    test(
      'blocks removed API families without blocking catalog and episodes',
      () {
        for (final path in [
          '/api/channel/by/2/key/',
          '/api-user/newapi/like.php?action=showlist',
          '/api-user/newapi/like.php?action=show-list_fav&listid=5',
        ]) {
          expect(ContentPolicy.allowsApiPath(Uri.parse(path)), isFalse);
        }
        expect(
          ContentPolicy.allowsApiPath(Uri.parse('/api/season/by/serie/2/key/')),
          isTrue,
        );
        expect(
          ContentPolicy.allowsApiPath(Uri.parse('/api/movie/by/2/key/')),
          isTrue,
        );
      },
    );
  });
}
