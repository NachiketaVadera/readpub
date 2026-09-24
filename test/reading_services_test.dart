import 'dart:convert';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

Future<(EpubPublication, ReadingServices)> open({int perPosition = 256}) async {
  final book = await EpubPublication.open(FileAsset('test/fixtures/epub/reading.epub'));
  addTearDown(book.close);
  return (book, ReadingServices(book, charactersPerPosition: perPosition));
}

void main() {
  test('exposes spine CFI package paths including non-linear items', () async {
    final (book, _) = await open();
    expect(book.spine.map((item) => item.cfiPath.toString()), [
      '/6/2[ref-ch1]',
      '/6/4',
      '/6/6',
      '/6/8',
      '/6/10',
    ]);
    expect(book.spine.map((item) => item.linear), [true, false, true, true, true]);
    expect(book.spine[1].idref, 'notes');
    expect(book.spine.first.link, book.readingOrder.first);
  });

  test('spine items use displayable manifest fallbacks', () async {
    final book = await EpubPublication.open(
      FileAsset('test/fixtures/epub/fallbacks.epub'),
    );
    addTearDown(book.close);
    bool displayable(Link link) => link.type == 'application/xhtml+xml';
    final json = book.readingOrder[0];
    expect(book.fallbackFor(json, displayable)!.href, 'OEBPS/Text/data.xhtml');
    expect(
      book.fallbackFor(book.readingOrder[1], displayable)!.href,
      'OEBPS/Text/plate.xhtml',
    );
    expect(
      book.fallbackFor(book.readingOrder[2], displayable),
      same(book.readingOrder[2]),
    );
    expect(book.fallbackFor(json, (link) => false), isNull);

    final services = ReadingServices(book);
    expect((await services.documentText(json))!.text, 'Data fallback text');
    final positions = await services.positions();
    expect(positions.locators.first.href, 'OEBPS/Text/data.xhtml');
    expect(positions.forReadingOrder(1).single.href, 'OEBPS/Text/plate.xhtml');
    final locator = services.locatorFromLink(Link(href: json.href))!;
    expect(locator.href, 'OEBPS/Text/data.xhtml');
    final document = (await services.documentText(json))!;
    final cfi = services.publicationCfi(Link(href: locator.href), document.cfiAt(5))!;
    expect(cfi.toString(), 'epubcfi(/6/2!/4/2[d]/1:5)');
    expect((await services.locatorForCfi(cfi))!.href, 'OEBPS/Text/data.xhtml');
    expect(book.warnings.map((warning) => warning.code), contains('resource-missing'));
  });

  group('document text', () {
    test('parses and caches reading-order documents', () async {
      final (book, services) = await open();
      final first = await services.documentText(book.readingOrder.first);
      expect(first!.blocks.first.text, 'Chapter One');
      expect(first.text, contains('A café served naïve travellers.'));
      expect(await services.documentText(book.readingOrder.first), same(first));
      final image = book.resources.singleWhere((link) => link.type == 'image/png');
      expect(await services.documentText(image), isNull);
    });

    test('reports malformed documents and foreign links as typed failures', () async {
      final (book, services) = await open();
      await expectLater(
        services.documentText(book.readingOrder.last),
        throwsA(isA<ContentException>()),
      );
      await expectLater(
        services.documentText(Link(href: 'https://example.invalid/a.xhtml')),
        throwsA(isA<ResourceException>()),
      );
      await book.close();
      final fresh = ReadingServices(book);
      await expectLater(
        fresh.documentText(book.readingOrder.first),
        throwsA(isA<ResourceException>()),
      );
    });
  });

  group('positions', () {
    test('are deterministic, titled and cover every reading-order item', () async {
      final (book, services) = await open();
      final positions = await services.positions();
      final chapter = (await services.documentText(book.readingOrder.first))!;
      final chapterCount = (chapter.length + 255) ~/ 256;
      expect(positions.forReadingOrder(0), hasLength(chapterCount));
      expect(positions.forReadingOrder(1), hasLength(1));
      expect(positions.forReadingOrder(2), hasLength(1), reason: 'fixed layout');
      expect(positions.forReadingOrder(3), hasLength(1), reason: 'unreadable');
      expect(positions.total, chapterCount + 3);
      expect(positions.unreadable, ['OEBPS/Text/broken.xhtml']);
      for (var i = 0; i < positions.total; i++) {
        final locations = positions.locators[i].locations;
        expect(locations.position, i + 1);
        expect(locations.totalProgression, closeTo(i / positions.total, 1e-12));
      }
      final second = positions.locators[1];
      expect(second.locations.progression, closeTo(256 / chapter.length, 1e-12));
      expect(
        chapter.resolveCfi(EpubCfi.parse(second.locations.partialCfi!))!.start,
        256,
      );
      final titles = positions.forReadingOrder(0).map((locator) => locator.title);
      expect(titles.first, 'Chapter One');
      expect(titles.last, 'Second Section');
      expect(positions.locators[chapterCount].title, 'Chapter Two');
      expect(positions.forReadingOrder(2).single.title, 'Plate');
      expect(await services.positions(), same(positions));
    });

    test('convert progression and round-trip through a JSON cache', () async {
      final (book, services) = await open();
      final positions = await services.positions();
      expect(positions.positionAt(0, 0), 1);
      expect(positions.positionAt(0, 1), positions.forReadingOrder(0).length);
      expect(
        positions.positionAt(2, 0.9),
        positions.forReadingOrder(2).single.locations.position,
      );
      expect(positions.totalProgressionAt(0, 0), 0);
      expect(positions.totalProgressionAt(3, 1), 1);
      final decoded = PublicationPositions.fromJson(
        jsonDecode(jsonEncode(positions.toJson())),
      );
      expect(decoded.locators, positions.locators);
      expect(decoded.unreadable, positions.unreadable);
      final cached = ReadingServices(
        book,
        charactersPerPosition: 256,
        positions: decoded,
      );
      expect(await cached.positions(), same(decoded));
      expect(
        () => ReadingServices(book, positions: decoded),
        throwsArgumentError,
        reason: 'different characters per position',
      );
      final broken = positions.toJson()..['version'] = 99;
      expect(() => PublicationPositions.fromJson(broken), throwsFormatException);
      final shifted = jsonDecode(jsonEncode(positions.toJson())) as Map;
      (shifted['positions'] as List).removeLast();
      expect(() => PublicationPositions.fromJson(shifted), throwsFormatException);
    });
  });

  group('locators', () {
    test('are created from navigation links without reading content', () async {
      final (book, services) = await open();
      final section = book.tableOfContents.first.children.single;
      final locator = services.locatorFromLink(section)!;
      expect(locator.href, 'OEBPS/Text/one.xhtml');
      expect(locator.type, 'application/xhtml+xml');
      expect(locator.title, 'Second Section');
      expect(locator.locations.fragments, ['s2']);
      expect(locator.locations.progression, isNull);
      final plain = services.locatorFromLink(book.readingOrder[1])!;
      expect(plain.locations.progression, 0);
      expect(services.locatorFromLink(Link(href: 'https://example.invalid/')), isNull);
      expect(services.locatorFromLink(Link(href: '')), isNull);
    });

    test('from progression include CFI, text context, position and title', () async {
      final (book, services) = await open();
      await services.positions();
      final chapter = book.readingOrder.first;
      final locator = await services.locatorForProgression(chapter, 0.75);
      final document = (await services.documentText(chapter))!;
      final offset = (document.length * 0.75).round();
      expect(locator.locations.progression, 0.75);
      expect(
        document.resolveCfi(EpubCfi.parse(locator.locations.partialCfi!))!.start,
        offset,
      );
      expect(locator.text.before, document.text.substring(offset - 40, offset));
      expect(locator.text.highlight, isNull);
      expect(locator.locations.position, 1 + offset ~/ 256);
      expect(locator.title, 'Second Section');
      expect(() => services.locatorForProgression(chapter, 1.5), throwsArgumentError);
    });

    test('convert publication CFIs, corrections and content selections', () async {
      final (book, services) = await open();
      final chapter = book.readingOrder.first;
      final document = (await services.documentText(chapter))!;
      final start = document.text.indexOf('café');
      final selection = document.cfiForRange(start, start + 4);
      final full = services.publicationCfi(chapter, selection)!;
      expect(full.toString(), startsWith('epubcfi(/6/2[ref-ch1]!/4/'));
      final fromFull = (await services.locatorForCfi(full))!;
      final fromContent = (await services.locatorForCfi(selection, link: chapter))!;
      expect(fromFull, fromContent);
      expect(fromFull.text.highlight, 'café');
      expect(fromFull.locations.partialCfi, selection.start.expression);
      // A manifest ID assertion, as some reading systems write, and a stale
      // itemref index corrected by its itemref ID.
      final manifestId = EpubCfi.parse(
        full.toString().replaceFirst('/6/2[ref-ch1]', '/6/2[ch1]'),
      );
      expect((await services.locatorForCfi(manifestId))!.text.highlight, 'café');
      final moved = EpubCfi.parse(
        full.toString().replaceFirst('/6/2[ref-ch1]', '/6/8[ref-ch1]'),
      );
      expect((await services.locatorForCfi(moved))!.href, chapter.href);
      final notes = (await services.locatorForCfi(
        EpubCfi.parse('epubcfi(/6/4!/4/2/1:7)'),
      ))!;
      expect(notes.href, 'OEBPS/Text/notes.xhtml');
      expect(notes.text.after, startsWith('about the whale'));
      expect(notes.locations.position, isNull);
      final packageOnly = (await services.locatorForCfi(
        EpubCfi.parse('epubcfi(/6/6)'),
      ))!;
      expect(packageOnly.href, 'OEBPS/Text/two.xhtml');
      expect(packageOnly.locations.progression, 0);
      expect(await services.locatorForCfi(EpubCfi.parse('epubcfi(/6/99!/4)')), isNull);
      expect(await services.locatorForCfi(EpubCfi.parse('epubcfi(/4/2!/4)')), isNull);
      expect(
        await services.locatorForCfi(EpubCfi.parse('/4/2[missing]'), link: chapter),
        isNull,
      );
    });

    test('from text ranges support application search indexes', () async {
      final (book, services) = await open();
      final chapter = book.readingOrder[1];
      final document = (await services.documentText(chapter))!;
      final start = document.text.indexOf('Ishmael');
      final locator = await services.locatorForTextRange(chapter, start, start + 7);
      expect(locator.text.highlight, 'Ishmael');
      expect(locator.title, 'Chapter Two');
      expect(() => services.locatorForTextRange(chapter, 5, 500), throwsRangeError);
    });
  });

  test('points between blocks resolve by their CFI', () async {
    final (book, services) = await open();
    final chapter = book.readingOrder.first;
    final document = (await services.documentText(chapter))!;
    var separators = 0;
    for (var offset = 0; offset < document.length; offset++) {
      if (document.text[offset] != '\n') continue;
      separators++;
      final locator = await services.locatorForTextRange(chapter, offset, offset);
      final resolution = (await services.resolve(locator))!;
      expect(resolution.match, LocatorMatch.cfi, reason: 'offset $offset');
      expect(resolution.start, offset + 1);
    }
    expect(separators, document.blocks.length - 1);
  });

  group('restoration', () {
    late EpubPublication book;
    late ReadingServices services;
    late DocumentText document;
    late Locator saved;

    setUp(() async {
      (book, services) = await open();
      await services.positions();
      document = (await services.documentText(book.readingOrder.first))!;
      final start = document.text.indexOf('whale surfaced');
      saved = await services.locatorForTextRange(
        book.readingOrder.first,
        start,
        start + 5,
      );
    });

    Future<LocatorResolution> resolve(Locator locator) async =>
        (await services.resolve(locator))!;

    test('uses a valid CFI that agrees with the locator text', () async {
      final resolution = await resolve(saved);
      expect(resolution.match, LocatorMatch.cfi);
      expect(document.text.substring(resolution.start, resolution.end), 'whale');
      expect(resolution.contentCfi!.isRange, isTrue);
      expect(resolution.cfi.toString(), startsWith('epubcfi(/6/2[ref-ch1]!'));
      expect(resolution.readingOrderIndex, 0);
      expect(resolution.locator.text.highlight, 'whale');
      expect(resolution.locator.locations.position, saved.locations.position);
    });

    test('recovers stale CFIs from text, then falls back in order', () async {
      Locator variant({
        String? cfi,
        double? progression,
        int? position,
        List<String> fragments = const [],
        LocatorText text = const LocatorText(),
      }) => Locator(
        href: saved.href,
        type: saved.type,
        locations: Locations(
          fragments: fragments,
          progression: progression,
          position: position,
          otherLocations: {'partialCfi': ?cfi},
        ),
        text: text,
      );

      final stale = await resolve(
        variant(cfi: '/4/10[p4]/1:3', text: saved.text, progression: 0.1),
      );
      expect(stale.match, LocatorMatch.text);
      expect(document.text.substring(stale.start, stale.end), 'whale');
      expect(stale.locator.locations.partialCfi, saved.locations.partialCfi);

      final contextOnly = await resolve(
        variant(
          text: LocatorText(before: saved.text.before, after: 'whale surfaced.'),
        ),
      );
      expect(contextOnly.match, LocatorMatch.text);
      expect(contextOnly.start, document.text.indexOf('whale surfaced'));

      final nearest = await resolve(
        variant(text: const LocatorText(highlight: 'whale'), progression: 0.9),
      );
      expect(nearest.start, document.text.indexOf('whale dived'));

      final unmatched = await resolve(
        variant(
          cfi: '/4/26[p12]/1:58',
          text: const LocatorText(highlight: 'kraken'),
        ),
      );
      expect(unmatched.match, LocatorMatch.cfi, reason: 'edited text keeps the CFI');

      final fragment = await resolve(variant(fragments: ['s2']));
      expect(fragment.match, LocatorMatch.fragment);
      expect(fragment.start, document.offsetOfId('s2'));

      final progression = await resolve(variant(progression: 0.5));
      expect(progression.match, LocatorMatch.progression);
      expect(progression.start, (document.length * 0.5).round());

      final position = await resolve(variant(position: 3));
      expect(position.match, LocatorMatch.position);
      expect(position.start, 512);

      final start = await resolve(variant(cfi: 'not a cfi'));
      expect(start.match, LocatorMatch.start);
      expect(start.start, 0);
    });

    test('preserves extensions and resolves resources without text', () async {
      final extended = saved.copyWith(
        locations: saved.locations.copyWith(
          otherLocations: {...saved.locations.otherLocations, 'x-app': 7},
        ),
      );
      expect((await resolve(extended)).locator.locations.otherLocations['x-app'], 7);
      final image = await resolve(
        Locator(
          href: 'OEBPS/Text/plate.png',
          type: 'image/png',
          locations: Locations(progression: 0.5),
        ),
      );
      expect(image.match, LocatorMatch.progression);
      expect(image.readingOrderIndex, isNull);
      expect(image.contentCfi, isNull);
      expect(
        await services.resolve(Locator(href: 'missing.xhtml', type: 'text/html')),
        isNull,
      );
    });
  });

  group('search', () {
    Future<List<SearchResult>> run(
      ReadingServices services,
      String query, [
      SearchOptions options = const SearchOptions(),
    ]) => services.search(query, options: options).toList();

    test('finds case- and diacritic-insensitive matches in reading order', () async {
      final (book, services) = await open();
      final results = await run(services, 'whale');
      expect(results.map((result) => result.locator.text.highlight), [
        'whale',
        'whale',
        'WHALE',
        'whale',
      ]);
      expect(results.map((result) => result.readingOrderIndex), [0, 0, 1, 1]);
      for (final result in results) {
        final located = await services.locatorForCfi(result.cfi!);
        expect(located!.text.highlight, result.locator.text.highlight);
      }
      expect(results.first.locator.title, 'Chapter One');
      expect(results[1].locator.title, 'Second Section');
      expect(results.first.locator.text.before, endsWith('sea. A '));
      final cafe = await run(services, 'CAFE SERVED NAIVE');
      expect(cafe.single.locator.text.highlight, 'café served naïve');
    });

    test('applies sensitivity, whole-word and result options', () async {
      final (book, services) = await open();
      Future<int> count(String query, SearchOptions options) async =>
          (await run(services, query, options)).length;
      expect(await count('cafe', const SearchOptions(diacriticSensitive: true)), 0);
      expect(await count('café', const SearchOptions(diacriticSensitive: true)), 1);
      expect(await count('WHALE', const SearchOptions(caseSensitive: true)), 1);
      expect(await count('whale', const SearchOptions(wholeWord: true)), 3);
      expect(await count('whale', const SearchOptions(maxResults: 2)), 2);
      expect(await count('   ', const SearchOptions()), 0);
      final narrow = await run(
        services,
        'Ishmael',
        const SearchOptions(contextLength: 3),
      );
      expect(narrow.single.locator.text.before, 'y.\n');
      expect(await services.search('whale').first, isA<SearchResult>());
      await expectLater(
        services.search('whale', options: const SearchOptions(maxResults: 0)).toList(),
        throwsArgumentError,
      );
      await expectLater(
        services
            .search('x', options: const SearchOptions(skipUnreadable: false))
            .toList(),
        throwsA(isA<ContentException>()),
      );
    });

    test('includes positions once computed', () async {
      final (_, services) = await open();
      expect(
        (await run(services, 'Ishmael')).single.locator.locations.position,
        isNull,
      );
      final positions = await services.positions();
      final result = (await run(services, 'Ishmael')).single;
      expect(
        result.locator.locations.position,
        positions.forReadingOrder(1).single.locations.position,
      );
      expect(result.locator.locations.totalProgression, greaterThan(0.7));
    });
  });
}
