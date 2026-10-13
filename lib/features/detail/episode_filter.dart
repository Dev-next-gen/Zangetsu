import '../../core/models/episode.dart';

/// CloudStream-style chunk size for long season navigation (1–50, 51–100, …).
const kEpisodeRangeChunk = 50;

/// Filters [episodes] by a case-insensitive substring [query] over each
/// episode's title and number. An empty/whitespace query returns the list
/// unchanged. A whole-number match ignores the trailing `.0` (so "12" matches
/// episode `12.0`, and "1.5" matches `1.5`).
List<Episode> filterEpisodes(List<Episode> episodes, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return episodes;
  return episodes.where((e) {
    if (e.title.toLowerCase().contains(q)) return true;
    final n = e.number;
    if (n != null) {
      final s = n == n.roundToDouble() ? n.toInt().toString() : n.toString();
      if (s.contains(q)) return true;
    }
    return false;
  }).toList();
}

/// How many range chips a list of [total] episodes needs.
int episodeRangeCount(int total) => (total / kEpisodeRangeChunk).ceil();

/// Which range chip holds [localIndex] in the filtered list (-1 → 0).
int episodeRangeIndex(int localIndex, {int? total, bool reversed = false}) {
  if (localIndex < 0) return 0;
  if (!reversed || total == null) return localIndex ~/ kEpisodeRangeChunk;
  final firstRangeLength = total % kEpisodeRangeChunk;
  if (firstRangeLength == 0 || localIndex < firstRangeLength) return 0;
  return 1 + (localIndex - firstRangeLength) ~/ kEpisodeRangeChunk;
}

/// Position for a 1-based episode number when the source omits episode
/// numbers and the row falls back to its list position.
int episodePositionForNumber(int number, int total, {bool reversed = false}) =>
    reversed ? total - number : number - 1;

/// Inclusive [start], exclusive [end] slice bounds for [rangeIndex].
({int start, int end}) episodeRangeSlice(
  int rangeIndex,
  int total, {
  bool reversed = false,
}) {
  if (reversed) {
    final remainder = total % kEpisodeRangeChunk;
    final firstRangeLength = remainder == 0 ? kEpisodeRangeChunk : remainder;
    final index = rangeIndex.clamp(0, episodeRangeCount(total));
    final start =
        (index == 0 ? 0 : firstRangeLength + (index - 1) * kEpisodeRangeChunk)
            .clamp(0, total);
    final end = (start + (index == 0 ? firstRangeLength : kEpisodeRangeChunk))
        .clamp(0, total);
    return (start: start, end: end);
  }
  final start = (rangeIndex * kEpisodeRangeChunk).clamp(0, total);
  final end = (start + kEpisodeRangeChunk).clamp(0, total);
  return (start: start, end: end);
}

/// Display label for a range chip, e.g. `1–50` or `51–60`.
String episodeNumLabel(Episode e, int fallback) =>
    (e.number?.toInt() ?? fallback).toString();

String episodeRangeLabel(
  List<Episode> episodes,
  int rangeIndex, {
  bool reversed = false,
}) {
  final total = episodes.length;
  if (total == 0) return '';
  final safeRangeIndex = rangeIndex.clamp(0, episodeRangeCount(total) - 1);
  final slice = episodeRangeSlice(safeRangeIndex, total, reversed: reversed);
  final start = slice.start;
  final end = slice.end - 1;
  final fallbackStart = reversed ? total - start : start + 1;
  final fallbackEnd = reversed ? total - end : end + 1;
  return '${episodeNumLabel(episodes[start], fallbackStart)}'
      '–${episodeNumLabel(episodes[end], fallbackEnd)}';
}
