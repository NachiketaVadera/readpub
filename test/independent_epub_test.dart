import 'dart:convert';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

Future<EpubPublication> openFixture(String name) =>
    EpubPublication.open(FileAsset('test/fixtures/epub/$name.epub'));

void main() {
  test('EPUB3 exposes normalized content and navigation directly', () async {
    final publication = await openFixture('epub3-basic');
    addTearDown(publication.close);
    expect(publication.metadata.title, 'Fixture');
    expect(publication.readingOrder.single.href, 'OEBPS/Text/chapter%20one.xhtml');
    expect(publication.tableOfContents.single.title, 'Chapter One');
    expect(
      publication.tableOfContents.single.href,
      'OEBPS/Text/chapter%20one.xhtml#start',
    );
    expect(
      utf8.decode(await publication.resource(publication.readingOrder.single).read()),
      contains('<h1 id="start">Hello</h1>'),
    );
  });

  test(
    'rich EPUB3 preserves refinements, non-linear resources and nested navigation',
    () async {
      final publication = await openFixture('epub3-rich');
      addTearDown(publication.close);
      expect(publication.metadata.title, 'Example & World');
      expect(publication.metadata.authors.single.name, 'Ada Author');
      expect(publication.metadata.authors.single.fileAs, 'Author, Ada');
      expect(publication.metadata.languages, ['en', 'fr']);
      expect(
        publication.metadata.raw.any(
          (value) => value.id == 'custom' && value.value == 'retained',
        ),
        isTrue,
      );
      expect(publication.readingOrder, hasLength(1));
      expect(
        publication.resources.any((link) => link.href.endsWith('appendix.xhtml')),
        isTrue,
      );
      expect(
        publication.resources
            .singleWhere((link) => link.href.endsWith('cover.jpg'))
            .rels,
        contains('cover'),
      );
      final part = publication.tableOfContents.single;
      expect(part.title, 'Part One');
      expect(part.children.single.title, 'Chapter One');
      expect(part.children.single.href, 'OEBPS/Text/chapter%20one.xhtml?q=1#start');
      expect(publication.landmarks.single.rels, contains('bodymatter'));
      expect(publication.pageList.single.title, '1');
      expect(
        publication.otherCollections.where((value) => value.role == 'preview'),
        hasLength(1),
      );
    },
  );

  test('EPUB2 NCX and legacy guide retain their trees and targets', () async {
    final publication = await openFixture('epub2-ncx');
    addTearDown(publication.close);
    expect(publication.metadata.authors.single.name, 'Legacy Author');
    expect(publication.metadata.authors.single.fileAs, 'Author, Legacy');
    expect(publication.tableOfContents.single.title, 'Part');
    expect(publication.tableOfContents.single.children.single.title, 'Chapter One');
    expect(publication.pageList.single.href, 'OEBPS/Text/chapter%20one.xhtml#p1');
    expect(publication.landmarks.single.href, 'OEBPS/Text/chapter%20one.xhtml#start');
  });

  test(
    'inherited xml:base resolves package and manifest directory references',
    () async {
      final publication = await openFixture('xml-base');
      addTearDown(publication.close);
      expect(
        publication.readingOrder.single.href,
        'OEBPS/Assets/Text/chapter%20one.xhtml',
      );
      expect(
        publication.tableOfContents.single.href,
        'OEBPS/Assets/Text/chapter%20one.xhtml#start',
      );
      expect(
        await publication.resource(publication.readingOrder.single).read(),
        isNotEmpty,
      );
    },
  );

  test('leaking and path-absolute URLs resolve at the container root', () async {
    final leaking = await openFixture('unsafe-path');
    addTearDown(leaking.close);
    // ../../outside.xhtml from OEBPS/ stops at the root, as EPUB Reading
    // Systems 3.3 requires; the file does not exist there.
    expect(leaking.readingOrder.single.href, 'outside.xhtml');
    expect(
      leaking.warnings.map((warning) => warning.code),
      containsAll(['url-leaks-container', 'resource-missing']),
    );
    await expectLater(
      leaking.resource(leaking.readingOrder.single).read(),
      throwsA(isA<ResourceException>()),
    );
    final absolute = await openFixture('path-absolute');
    addTearDown(absolute.close);
    expect(absolute.readingOrder.single.href, 'OEBPS/Text/chapter%20one.xhtml');
    expect(
      absolute.tableOfContents.single.href,
      'OEBPS/Text/chapter%20one.xhtml#start',
    );
    expect(
      absolute.warnings.map((warning) => warning.code),
      contains('url-path-absolute'),
    );
    expect(await absolute.resource(absolute.readingOrder.single).read(), isNotEmpty);
  });

  test('navigation images and metadata direction follow EPUB 3.3', () async {
    final book = await openFixture('nav-direction');
    addTearDown(book.close);
    expect(book.tableOfContents.map((link) => link.title), [
      'Pictured start',
      'Titled link',
    ]);
    final titles = book.metadata.titles;
    expect(titles.map((title) => title.direction), ['ltr', 'rtl']);
    expect(titles.last.language, 'he');
    expect(book.metadata.authors.map((author) => author.direction), ['auto', 'ltr']);
    expect(titles.last.toJson()['direction'], 'rtl');
  });

  test('processes packages with versions below 3.0', () async {
    final publication = await openFixture('version-zero');
    addTearDown(publication.close);
    expect(publication.metadata.title, 'Fixture');
    expect(
      publication.warnings.map((warning) => warning.code),
      contains('package-version-unsupported'),
    );
  });

  for (final name in [
    'broken-spine',
    'duplicate-manifest',
    'fallback-cycle',
    'entity-attack',
    'foreign-namespace',
  ]) {
    test('rejects $name without unsafe recovery', () async {
      await expectLater(openFixture(name), throwsA(isA<PublicationException>()));
    });
  }

  test('missing navigation is recoverable and diagnosed', () async {
    final publication = await openFixture('missing-nav');
    addTearDown(publication.close);
    expect(publication.readingOrder, hasLength(1));
    expect(publication.tableOfContents, isEmpty);
    expect(publication.warnings, isNotEmpty);
  });

  test('remote manifest resources are retained but never fetched implicitly', () async {
    final publication = await openFixture('remote-resource');
    addTearDown(publication.close);
    final remote = publication.resources.singleWhere(
      (link) => link.href.startsWith('https:'),
    );
    await expectLater(
      publication.resource(remote).read(),
      throwsA(isA<PublicationException>()),
    );
  });

  for (final name in ['idpf', 'adobe']) {
    test(
      'deobfuscates $name fonts including ranges beyond the obfuscated prefix',
      () async {
        final publication = await openFixture('font-$name');
        addTearDown(publication.close);
        final font = publication.resource(
          publication.resources.singleWhere((link) => link.href.endsWith('font.otf')),
        );
        expect(await font.read(), List.generate(1300, (index) => index % 251));
        expect(
          await font.read(start: 1000, end: 1100),
          List.generate(100, (index) => (index + 1000) % 251),
        );
        await expectLater(font.read(start: -1), throwsA(isA<PublicationException>()));
      },
    );
  }

  test('unsupported encryption blocks resource bytes', () async {
    final publication = await openFixture('font-unsupported');
    addTearDown(publication.close);
    final font = publication.resources.singleWhere(
      (link) => link.href.endsWith('font.otf'),
    );
    await expectLater(
      publication.resource(font).read(),
      throwsA(isA<ResourceException>()),
    );
  });
}
