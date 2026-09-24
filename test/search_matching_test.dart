import 'package:readpub/src/search/search.dart';
import 'package:test/test.dart';

List<String> find(
  String query,
  String source, [
  SearchOptions options = const SearchOptions(),
]) => [
  for (final (start, end) in SearchMatcher(query, options).matches(source))
    source.substring(start, end),
];

void main() {
  test('folds case, diacritics and decomposed marks to source ranges', () {
    expect(find('resume', 'Résumé and RESUME and résumé'), [
      'Résumé',
      'RESUME',
      'résumé',
    ]);
    expect(find('ΟΔΟΣ', 'οδός'), ['οδός']);
    expect(find('ёлка', 'Елка'), ['Елка']);
    expect(find('istanbul', 'İstanbul'), ['İstanbul']);
    expect(find('lodz', 'Łódź'), ['Łódź']);
    expect(find('שלום', 'שָׁלוֹם'), ['שָׁלוֹם']);
  });

  test('keeps marks that distinguish words in other scripts', () {
    expect(find('か', 'が'), isEmpty);
    expect(find('कि', 'क'), isEmpty);
  });

  test('normalizes spaces and ignores soft hyphens and zero-width spaces', () {
    expect(find('two  words', 'two \n words'), ['two \n words']);
    expect(find('hyphenation', 'hy­phen​ation'), ['hy­phen​ation']);
    expect(find(' padded ', 'a padded b'), ['padded']);
  });

  test('matches surrogate pairs and whole words', () {
    expect(find('😀x', 'a😀xb'), ['😀x']);
    expect(
      find('cat', 'cat concat cat_ cats cat.', const SearchOptions(wholeWord: true)),
      ['cat', 'cat', 'cat'],
    );
    expect(find('aa', 'aaaa'), ['aa', 'aa']);
  });

  test('respects sensitivity options', () {
    expect(
      find('Cafe', 'café CAFE', const SearchOptions(caseSensitive: true)),
      isEmpty,
    );
    expect(find('CAFE', 'café CAFE', const SearchOptions(caseSensitive: true)), [
      'CAFE',
    ]);
    expect(find('cafe', 'café cafe', const SearchOptions(diacriticSensitive: true)), [
      'cafe',
    ]);
    expect(
      () => SearchMatcher('x', const SearchOptions(contextLength: -1)),
      throwsArgumentError,
    );
  });
}
