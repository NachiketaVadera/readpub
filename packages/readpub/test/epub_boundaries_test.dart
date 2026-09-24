import 'dart:convert';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

Future<EpubPublication> open(
  String name, [
  EpubParserOptions options = const EpubParserOptions(),
]) =>
    EpubPublication.open(FileAsset('test/fixtures/epub/$name.epub'), options: options);

void main() {
  for (final (label, options) in [
    ('bytes', const EpubParserOptions(maxXmlBytes: 100)),
    ('elements', const EpubParserOptions(maxXmlElements: 4)),
    ('XML depth', const EpubParserOptions(maxXmlDepth: 2)),
    ('navigation count', const EpubParserOptions(maxNavigationItems: 1)),
    ('navigation depth', const EpubParserOptions(maxNavigationDepth: 1)),
  ]) {
    test('$label limits cannot be downgraded to navigation warnings', () async {
      await expectLater(
        open('epub3-rich', options),
        throwsA(isA<EpubLimitException>()),
      );
    });
  }
  test('leaking navigation URIs stay inside the container', () async {
    final book = await open('unsafe-nav');
    addTearDown(book.close);
    expect(book.tableOfContents.single.href, 'escape');
    expect(book.warnings.map((w) => w.code), contains('url-leaks-container'));
  });
  test('encoded dot segments are clamped like literal ones', () async {
    // Percent-encoded dots are dot segments in URL parsing, so they cannot
    // bypass the container root either.
    final book = await open('encoded-traversal');
    addTearDown(book.close);
    expect(book.readingOrder.single.href, 'outside.xhtml');
    expect(book.warnings.map((w) => w.code), contains('url-leaks-container'));
  });
  test('scheme-relative URIs remain fatal', () async {
    await expectLater(open('scheme-relative'), throwsA(isA<EpubSecurityException>()));
  });
  test('malformed optional nav falls back to NCX with diagnostics', () async {
    final book = await open('nav-ncx-fallback');
    addTearDown(book.close);
    expect(book.tableOfContents.single.children.single.title, 'Chapter One');
    expect(book.warnings.map((w) => w.code), contains('navigation-invalid'));
  });
  test('UTF16 package metadata is decoded', () async {
    final book = await open('utf16');
    addTearDown(book.close);
    expect(book.metadata.description, 'Café 雪');
  });
  test('container rootfile is a literal path, not a percent encoded URI', () async {
    final book = await open('encoded-root');
    addTearDown(book.close);
    expect(book.links.first.href, 'OEBPS/100%25%20book.opf');
    expect(book.metadata.title, 'Fixture');
  });
  test('Unicode and literal percent paths round trip through resources', () async {
    final book = await open('literal-percent');
    addTearDown(book.close);
    expect(
      await book.resource(book.readingOrder.single).readAsString(),
      contains('Hello'),
    );
  });
  test('missing optional display metadata has diagnostics', () async {
    final book = await open('missing-metadata');
    addTearDown(book.close);
    expect(book.metadata.title, '');
    expect(book.metadata.languages, isEmpty);
    expect(book.warnings.map((w) => w.code), contains('metadata-missing-title'));
  });
  test('invalid dates and duration are diagnosed and preserved raw', () async {
    final book = await open('invalid-date');
    addTearDown(book.close);
    expect(book.metadata.published, isNull);
    expect(book.metadata.duration, isNull);
    expect(book.metadata.raw.any((r) => r.value == '2024-02-31'), isTrue);
    expect(book.warnings.map((w) => w.code), contains('metadata-invalid-published'));
  });
  test('advanced metadata and resource relationships are normalized', () async {
    final book = await open('epub3-rich');
    addTearDown(book.close);
    final metadata = book.metadata;
    expect(metadata.subtitle, 'A Subtitle');
    expect(metadata.editors.single.name, 'Ed Editor');
    expect(metadata.translators.single.name, 'Tia Translator');
    expect(metadata.publishers.single.name, 'Example Press');
    expect(
      metadata.subjects.single,
      const Subject('Computing', code: 'COM000000', scheme: 'BISAC'),
    );
    expect(metadata.published, DateTime(2024, 5, 6));
    expect(metadata.modified, DateTime.utc(2025, 1, 2, 3, 4, 5));
    expect(
      metadata.duration,
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
    );
    expect(metadata.numberOfPages, 123);
    expect(metadata.readingProgression, 'rtl');
    expect(metadata.layout, 'fixed');
    expect(metadata.orientation, 'landscape');
    expect(metadata.accessibility['accessMode'], ['textual']);
    expect(book.readingOrder.single.properties['orientation'], 'portrait');
    expect(book.readingOrder.single.properties['page'], 'left');
    expect(book.readingOrder.single.properties['media-overlay'], 'OEBPS/overlay.smil');
    expect(
      book.resources.singleWhere((l) => l.href.endsWith('overlay.smil')).duration,
      const Duration(milliseconds: 12250),
    );
    expect(
      book.resources
          .singleWhere((l) => l.href.endsWith('foreign.bin'))
          .alternates
          .single
          .href,
      book.readingOrder.single.href,
    );
    expect(
      book.otherCollections
          .singleWhere((c) => c.role == 'bindings')
          .links
          .single
          .properties['handles'],
      'application/x-example',
    );
    expect(jsonDecode(jsonEncode(metadata.toJson())), isA<Map<String, Object?>>());
  });
  test('manifest lookup ignores navigation fragments and queries', () async {
    final book = await open('epub3-basic');
    final href = book.readingOrder.single.href;
    final resource = book.get('$href?q=1#start');
    expect(resource, isNotNull);
    expect(await resource!.readAsString(), contains('Hello'));
    expect(book.get('missing'), isNull);
    await book.close();
    await expectLater(resource.read(), throwsA(isA<PublicationException>()));
  });
  test('encryption declarations remain inspectable', () async {
    final book = await open('font-unsupported');
    addTearDown(book.close);
    expect(book.encryption['OEBPS/font.otf'], 'urn:example:unsupported');
    expect(() => book.encryption.clear(), throwsUnsupportedError);
  });
  test('value models copy collections and implement structural equality', () {
    final children = <Link>[Link(href: 'chapter.xhtml')];
    final link = Link(href: '', children: children, rels: {'toc', 'contents'});
    children.clear();
    final equal = Link(
      href: '',
      children: [Link(href: 'chapter.xhtml')],
      rels: {'contents', 'toc'},
    );
    expect(link, equal);
    expect(link.hashCode, equal.hashCode);
    expect(() => link.children.clear(), throwsUnsupportedError);
    final values = <String>['textual'];
    final metadata = Metadata(title: 'Book', accessibility: {'accessMode': values});
    values.clear();
    expect(metadata.accessibility['accessMode'], ['textual']);
    expect(() => metadata.accessibility['accessMode']!.clear(), throwsUnsupportedError);
  });
}
