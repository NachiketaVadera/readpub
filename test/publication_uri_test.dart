import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeArchivePath', () {
    test('normalizes benign dot segments without decoding percent signs', () {
      expect(
        normalizeArchivePath('OPS/./Text/../chapter%2Fone.xhtml'),
        'OPS/chapter%2Fone.xhtml',
      );
    });

    test('rejects unsafe paths', () {
      for (final path in <String>[
        '../book.xhtml',
        '/book.xhtml',
        r'OPS\book.xhtml',
        'C:book.xhtml',
      ]) {
        expect(() => normalizeArchivePath(path), throwsA(isA<ArchiveException>()));
      }
    });
  });

  group('resolvePublicationReference', () {
    test('validates the entire encoded base path', () {
      for (final base in [
        'OPS/bad%.xhtml',
        'OPS/book.xhtml?query',
        '/OPS/book.xhtml',
      ]) {
        expect(
          () => resolvePublicationReference('next.xhtml', basePath: base),
          throwsA(isA<ResourceException>()),
        );
        expect(
          () => resolvePublicationReference('#here', basePath: base),
          throwsA(isA<ResourceException>()),
        );
      }
      expect(
        resolvePublicationReference('next.xhtml', basePath: 'OPS%2520/book.xhtml'),
        'OPS%20/next.xhtml',
      );
    });

    test('decodes exactly once and resolves against a document', () {
      expect(
        resolvePublicationReference(
          '../Images/cat%20one.png?edition=2#figure',
          basePath: 'OPS/Text/chapter.xhtml',
        ),
        'OPS/Images/cat one.png',
      );
      expect(resolvePublicationReference('literal%2520.txt'), 'literal%20.txt');
      expect(
        resolvePublicationReference('#chapter', basePath: 'OPS/book.xhtml'),
        'OPS/book.xhtml',
      );
    });

    test(
      'rejects external, root-escaping, malformed, and encoded-separator references',
      () {
        for (final reference in <String>[
          'https://example.com/book.xhtml',
          '/book.xhtml',
          '../book.xhtml',
          'text%2Fchapter.xhtml',
          'text%5Cchapter.xhtml',
          'bad%2.xhtml',
          'bad\u0001.xhtml',
        ]) {
          expect(
            () => resolvePublicationReference(reference),
            throwsA(isA<ResourceException>()),
          );
        }
      },
    );
  });
}
