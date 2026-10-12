import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/ui/mobile_hero_art.dart';

void main() {
  test('uses original-size TMDB portrait art for tall mobile heroes', () {
    expect(
      mobileHeroArt(
        'https://image.tmdb.org/t/p/w500/poster.jpg',
        'https://image.tmdb.org/t/p/w780/backdrop.jpg',
      ),
      'https://image.tmdb.org/t/p/original/poster.jpg',
    );
  });

  test('keeps the wide image when TMDB has no portrait', () {
    expect(
      mobileHeroArt(null, 'https://image.tmdb.org/t/p/w780/backdrop.jpg'),
      'https://image.tmdb.org/t/p/w780/backdrop.jpg',
    );
  });

  test('does not change non-TMDB artwork', () {
    expect(
      mobileHeroArt('https://anime/cover.jpg', 'https://anime/banner.jpg'),
      'https://anime/banner.jpg',
    );
  });
}
