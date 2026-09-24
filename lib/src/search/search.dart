import '../cfi/epub_cfi.dart';
import '../locator/locator.dart';
import 'folding_table.dart';

/// Full-text search over a publication.
///
/// `ReadingServices` implements this interface by scanning content documents
/// lazily. Applications can substitute an implementation backed by a
/// persistent index, building that index from `ReadingServices.documentText`
/// and converting hits with `ReadingServices.locatorForTextRange`.
abstract interface class SearchService {
  /// Streams matches for [query] in reading order.
  ///
  /// Cancelling the subscription stops the search.
  Stream<SearchResult> search(
    String query, {
    SearchOptions options = const SearchOptions(),
  });
}

/// Options controlling text matching and result size.
final class SearchOptions {
  /// Creates search options.
  ///
  /// [maxResults] must be positive and [contextLength] not negative.
  const SearchOptions({
    this.caseSensitive = false,
    this.diacriticSensitive = false,
    this.wholeWord = false,
    this.maxResults = 1000,
    this.contextLength = 40,
    this.skipUnreadable = true,
  });

  /// Whether letter case must match. Otherwise simple Unicode lowercase
  /// mapping is used; full case folding such as `ß` to `ss` is not applied.
  final bool caseSensitive;

  /// Whether diacritics must match. Otherwise nonspacing marks are ignored
  /// and precomposed Latin, Greek, Cyrillic, Arabic and Hebrew letters match
  /// their base letters.
  final bool diacriticSensitive;

  /// Whether matches must start and end at word boundaries.
  ///
  /// Boundaries are letters, digits and marks; scripts written without spaces
  /// between words, such as Chinese, rarely have them.
  final bool wholeWord;

  /// The maximum number of results before the search stops.
  final int maxResults;

  /// The number of UTF-16 code units of context before and after each match.
  final int contextLength;

  /// Whether malformed or oversized documents are skipped rather than
  /// reported as stream errors. Resource access failures are always reported.
  final bool skipUnreadable;
}

/// A search match.
final class SearchResult {
  /// Creates a search result.
  const SearchResult({
    required this.locator,
    required this.readingOrderIndex,
    this.cfi,
  });

  /// The match location, with the matched text in `text.highlight`.
  final Locator locator;

  /// The index of the matching resource in the reading order.
  final int readingOrderIndex;

  /// The publication CFI range of the match, when the publication is an EPUB.
  final EpubCfi? cfi;
}

/// Text normalized for matching, with source offsets for each code unit.
final class FoldedText {
  FoldedText._(this.text, this._starts, this._ends);

  /// Normalizes [source] according to [options].
  ///
  /// Whitespace sequences become one space, soft hyphens and zero-width
  /// spaces are removed, and case and diacritics are folded unless
  /// [options] request sensitivity.
  factory FoldedText(String source, SearchOptions options) {
    final output = StringBuffer();
    final starts = <int>[];
    final ends = <int>[];
    var index = 0;
    var space = false;
    while (index < source.length) {
      final start = index;
      var rune = source.codeUnitAt(index++);
      if (_isHigh(rune) && index < source.length && _isLow(source.codeUnitAt(index))) {
        rune =
            0x10000 + ((rune - 0xd800) << 10) + (source.codeUnitAt(index++) - 0xdc00);
      }
      if (_isSearchSpace(rune)) {
        if (space) {
          ends[ends.length - 1] = index;
        } else {
          output.write(' ');
          starts.add(start);
          ends.add(index);
          space = true;
        }
        continue;
      }
      if (_isIgnorable(rune)) continue;
      space = false;
      final lowered = options.caseSensitive ? null : _lower(rune);
      for (final unitRune in lowered?.runes ?? [rune]) {
        var value = unitRune;
        if (!options.diacriticSensitive) {
          if (_isMark(value)) {
            // A removed mark still belongs to the preceding character.
            if (ends.isNotEmpty) ends[ends.length - 1] = index;
            continue;
          }
          value = _folding[value] ?? value;
        }
        final text = String.fromCharCode(value);
        output.write(text);
        for (var unit = 0; unit < text.length; unit++) {
          starts.add(start);
          ends.add(index);
        }
      }
    }
    return FoldedText._(output.toString(), starts, ends);
  }

  /// The normalized text.
  final String text;
  final List<int> _starts;
  final List<int> _ends;

  /// The source offset where normalized code unit [index] starts.
  int sourceStart(int index) => _starts[index];

  /// The source offset where normalized code unit [index] ends.
  int sourceEnd(int index) => _ends[index];
}

/// Finds non-overlapping matches of a folded query in source text.
final class SearchMatcher {
  /// Creates a matcher for [query], or throws an [ArgumentError] for invalid
  /// [options].
  SearchMatcher(String query, this.options)
    : query = FoldedText(query, options).text.trim() {
    if (options.maxResults <= 0 || options.contextLength < 0) {
      throw ArgumentError('Search limits are invalid.');
    }
  }

  /// The normalized query; empty queries match nothing.
  final String query;

  /// The matching options.
  final SearchOptions options;

  /// Returns match ranges in [source] as half-open source offsets.
  Iterable<(int, int)> matches(String source) sync* {
    if (query.isEmpty) return;
    final folded = FoldedText(source, options);
    var from = 0;
    while (true) {
      final index = folded.text.indexOf(query, from);
      if (index < 0) return;
      final start = folded.sourceStart(index);
      final end = folded.sourceEnd(index + query.length - 1);
      if (!options.wholeWord || _isWordBoundary(source, start, end)) {
        yield (start, end);
        from = index + query.length;
      } else {
        from = index + 1;
      }
    }
  }
}

final _folding = {
  for (var i = 0; i < foldingPairs.length; i += 2) foldingPairs[i]: foldingPairs[i + 1],
};

final _wordCharacter = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

bool _isWordBoundary(String source, int start, int end) {
  bool word(int index) {
    if (index < 0 || index >= source.length) return false;
    var begin = index;
    if (_isLow(source.codeUnitAt(index)) &&
        index > 0 &&
        _isHigh(source.codeUnitAt(index - 1))) {
      begin--;
    }
    final finish = _isHigh(source.codeUnitAt(begin)) && begin + 1 < source.length
        ? begin + 2
        : begin + 1;
    return _wordCharacter.hasMatch(source.substring(begin, finish));
  }

  return !word(start - 1) && !word(end);
}

String _lower(int rune) {
  if (rune >= 0x41 && rune <= 0x5a) return String.fromCharCode(rune + 32);
  if (rune < 0x80) return String.fromCharCode(rune);
  // Final sigma matches medial sigma, as case-insensitive matching expects.
  if (rune == 0x3c2) return 'σ';
  return String.fromCharCode(rune).toLowerCase();
}

bool _isHigh(int unit) => unit >= 0xd800 && unit <= 0xdbff;
bool _isLow(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

bool _isSearchSpace(int rune) =>
    (rune >= 0x09 && rune <= 0x0d) ||
    rune == 0x20 ||
    rune == 0x85 ||
    rune == 0xa0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200a) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202f ||
    rune == 0x205f ||
    rune == 0x3000;

bool _isIgnorable(int rune) =>
    rune == 0xad || rune == 0x200b || rune == 0x2060 || rune == 0xfeff;

// Combining diacritics and the vowel points of Hebrew and Arabic. Indic,
// Southeast Asian and kana marks are retained because they distinguish words.
bool _isMark(int rune) =>
    (rune >= 0x0300 && rune <= 0x036f) ||
    (rune >= 0x0483 && rune <= 0x0489) ||
    (rune >= 0x0591 && rune <= 0x05bd) ||
    rune == 0x05bf ||
    rune == 0x05c1 ||
    rune == 0x05c2 ||
    rune == 0x05c4 ||
    rune == 0x05c5 ||
    rune == 0x05c7 ||
    (rune >= 0x0610 && rune <= 0x061a) ||
    (rune >= 0x064b && rune <= 0x065f) ||
    rune == 0x0670 ||
    (rune >= 0x06d6 && rune <= 0x06dc) ||
    (rune >= 0x06df && rune <= 0x06e4) ||
    rune == 0x06e7 ||
    rune == 0x06e8 ||
    (rune >= 0x06ea && rune <= 0x06ed) ||
    (rune >= 0x1ab0 && rune <= 0x1aff) ||
    (rune >= 0x1dc0 && rune <= 0x1dff) ||
    (rune >= 0x20d0 && rune <= 0x20ff) ||
    (rune >= 0xfe20 && rune <= 0xfe2f);
