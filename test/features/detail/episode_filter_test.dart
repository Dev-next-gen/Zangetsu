import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/features/detail/episode_filter.dart';

Episode ep(String id, String title, double? number) =>
    Episode(id: id, title: title, number: number, url: 'u$id');

void main() {
  final eps = [
    ep('1', 'The Beginning', 1),
    ep('2', 'A New Threat', 2),
    ep('12', 'Twelfth Night', 12),
    ep('s1', 'OVA Special', 1.5),
    ep('u', 'Untitled', null),
  ];

  group('filterEpisodes', () {
    test('empty / whitespace query returns the list unchanged', () {
      expect(filterEpisodes(eps, ''), same(eps));
      expect(filterEpisodes(eps, '   '), same(eps));
    });

    test('matches title case-insensitively', () {
      final r = filterEpisodes(eps, 'threat');
      expect(r.map((e) => e.id), ['2']);
    });

    test('matches a whole number without the trailing .0', () {
      final r = filterEpisodes(eps, '12');
      expect(r.map((e) => e.id), ['12']); // "12" -> 12.0, not a title hit
    });

    test('matches a decimal number', () {
      final r = filterEpisodes(eps, '1.5');
      expect(r.map((e) => e.id), ['s1']);
    });

    test('title and number can both contribute matches', () {
      // "1" appears in numbers 1 and 12 (as "12"/"1"), and 1.5 -> "1.5".
      final r = filterEpisodes(eps, '1');
      expect(r.map((e) => e.id).toSet(), {'1', '12', 's1'});
    });

    test('no match returns empty', () {
      expect(filterEpisodes(eps, 'zzz'), isEmpty);
    });

    test('a numberless episode still matches on title', () {
      final r = filterEpisodes(eps, 'untitled');
      expect(r.map((e) => e.id), ['u']);
    });
  });

  group('episode range helpers', () {
    test('episodeRangeCount splits at 50', () {
      expect(episodeRangeCount(0), 0);
      expect(episodeRangeCount(1), 1);
      expect(episodeRangeCount(50), 1);
      expect(episodeRangeCount(51), 2);
      expect(episodeRangeCount(60), 2);
      expect(episodeRangeCount(100), 2);
      expect(episodeRangeCount(101), 3);
    });

    test('episodeRangeIndex maps local index to chunk', () {
      expect(episodeRangeIndex(-1), 0);
      expect(episodeRangeIndex(0), 0);
      expect(episodeRangeIndex(49), 0);
      expect(episodeRangeIndex(50), 1);
    });

    test('reversed range indexes account for the shorter leading range', () {
      expect(episodeRangeIndex(0, total: 60, reversed: true), 0);
      expect(episodeRangeIndex(9, total: 60, reversed: true), 0);
      expect(episodeRangeIndex(10, total: 60, reversed: true), 1);
      expect(episodeRangeIndex(59, total: 60, reversed: true), 1);
    });

    test('numberless jump positions follow the displayed order', () {
      expect(episodePositionForNumber(1, 60, reversed: true), 59);
      expect(episodePositionForNumber(60, 60, reversed: true), 0);
      expect(episodePositionForNumber(1, 60), 0);
    });

    test('episodeRangeSlice returns inclusive start, exclusive end', () {
      expect(episodeRangeSlice(0, 60), (start: 0, end: 50));
      expect(episodeRangeSlice(1, 60), (start: 50, end: 60));
      expect(episodeRangeSlice(0, 50), (start: 0, end: 50));
    });

    test('reversed slices mirror normal episode ranges', () {
      expect(episodeRangeSlice(0, 60, reversed: true), (start: 0, end: 10));
      expect(episodeRangeSlice(1, 60, reversed: true), (start: 10, end: 60));
      expect(episodeRangeSlice(0, 110, reversed: true), (start: 0, end: 10));
      expect(episodeRangeSlice(1, 110, reversed: true), (start: 10, end: 60));
      expect(episodeRangeSlice(2, 110, reversed: true), (start: 60, end: 110));
    });

    test('episodeRangeLabel uses episode numbers with fallbacks', () {
      final numbered = [
        for (var i = 1; i <= 60; i++) ep('$i', 'Ep $i', i.toDouble()),
      ];
      expect(episodeRangeLabel(numbered, 0), '1–50');
      expect(episodeRangeLabel(numbered, 1), '51–60');

      final partial = [ep('a', 'First', 51), ep('b', 'Second', null)];
      expect(episodeRangeLabel(partial, 0), '51–2');
    });

    test('reversed labels match their slices and numberless row labels', () {
      final reversedNumbered = [
        for (var i = 60; i >= 1; i--) ep('$i', 'Ep $i', i.toDouble()),
      ];
      expect(episodeRangeLabel(reversedNumbered, 0, reversed: true), '60–51');
      expect(episodeRangeLabel(reversedNumbered, 1, reversed: true), '50–1');

      final reversedNumberless = [
        for (var i = 60; i >= 1; i--) ep('$i', 'Ep $i', null),
      ];
      expect(episodeRangeLabel(reversedNumberless, 0, reversed: true), '60–51');
      expect(episodeRangeLabel(reversedNumberless, 1, reversed: true), '50–1');
    });
  });
}
