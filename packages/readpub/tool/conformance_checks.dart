/// Requirement checks for W3C EPUB 3 test publications, shared by
/// `tool/conformance.dart` and `test/w3c_suite_test.dart`.
library;

import 'dart:io';

import 'package:readpub/readpub.dart';

/// The result category of one test publication.
enum ConformanceOutcome {
  /// A requirement observable by this library was asserted and held.
  checked('checked'),

  /// The test requires or allows an error, and the expected error occurred.
  expectedError('expected-error'),

  /// Processing succeeded apart from a known defect in the test itself.
  suiteDefect('suite-defect'),

  /// Processing succeeded; the pass criteria need a reading system.
  processed('processed'),

  /// A failure or failed requirement check.
  problem('problem');

  const ConformanceOutcome(this.label);

  /// The report label.
  final String label;
}

/// The result of running one test publication.
final class ConformanceResult {
  /// Creates a result.
  ConformanceResult(this.id);

  /// The test identifier, from the file name.
  final String id;

  /// Failures, including failed checks.
  final List<String> problems = [];

  /// Parser warning codes.
  List<String> warnings = const [];

  /// The requirement check result: `pass`, a failure, or null without a check.
  String? check;

  /// The number of positions, when computed.
  int? positions;

  /// The outcome category.
  ConformanceOutcome outcome = ConformanceOutcome.problem;

  /// Serializes the result for reports.
  Map<String, Object?> toJson() => {
    'id': id,
    'outcome': outcome.label,
    'problems': problems,
    'warnings': warnings,
    'check': ?check,
    'positions': ?positions,
  };
}

/// Tests that require or allow an XML error.
const expectedContentErrors = {
  'pub-xml-external-id',
  'pub-xml-names',
  'pub-xml-non-validating_unclosed',
};

/// Container tests that must be rejected as in error.
const expectedOpenFailures = {'ocf-zip-comp', 'ocf-zip-mult'};

/// Tests whose manifests reference a file under the wrong path, with that path.
const knownSuiteDefects = {
  'lay-pp-spine-overrides_image-only-reflow': 'EPUB/page_2.png',
  'lay-pp-spine-overrides_image-spine-reflow': 'EPUB/page_2.png',
};

/// Processes [file] and checks its requirement, when one is known.
Future<ConformanceResult> runConformanceTest(File file, HttpClient client) async {
  final id = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.epub$'), '');
  final result = ConformanceResult(id);
  final EpubPublication book;
  try {
    book = await EpubPublication.open(FileAsset(file.path));
  } on PublicationException catch (error) {
    result.problems.add('open: $error');
    if (expectedOpenFailures.contains(id) && error is ArchiveException) {
      result.outcome = ConformanceOutcome.expectedError;
    }
    return result;
  }
  var contentErrors = 0;
  try {
    result.warnings = [for (final warning in book.warnings) warning.code];
    for (final link in [...book.readingOrder, ...book.resources]) {
      if (Uri.parse(link.href).hasScheme) continue;
      try {
        await book.resource(link).read();
      } on PublicationException catch (error) {
        result.problems.add('read ${link.href}: $error');
      }
    }
    final services = ReadingServices(book);
    final session = await EpubRenderSession.start(book);
    try {
      for (final link in book.readingOrder) {
        try {
          await services.documentText(link);
        } on ContentException catch (error) {
          contentErrors++;
          result.problems.add('text ${link.href}: $error');
        } on PublicationException catch (error) {
          result.problems.add('text ${link.href}: $error');
        }
        if (link.type == 'application/xhtml+xml' || link.type == 'text/html') {
          try {
            await session.prepare(link);
          } on ContentException catch (error) {
            contentErrors++;
            result.problems.add('prepare ${link.href}: $error');
          } on PublicationException catch (error) {
            result.problems.add('prepare ${link.href}: $error');
          }
        }
      }
      result.positions = (await services.positions()).total;
      final check = conformanceChecks[id];
      if (check != null) {
        final failure = await check(book, session, client);
        result.check = failure ?? 'pass';
        if (failure != null) result.problems.add('check: $failure');
      }
    } on PublicationException catch (error) {
      result.problems.add('services: $error');
    } finally {
      await session.close();
    }
  } finally {
    await book.close();
  }
  final defect = knownSuiteDefects[id];
  result.outcome = switch (result.problems) {
    [] when result.check == 'pass' => ConformanceOutcome.checked,
    [] => ConformanceOutcome.processed,
    final problems
        when expectedContentErrors.contains(id) && contentErrors == problems.length =>
      ConformanceOutcome.expectedError,
    final problems
        when defect != null && problems.every((problem) => problem.contains(defect)) =>
      ConformanceOutcome.suiteDefect,
    _ => ConformanceOutcome.problem,
  };
  return result;
}

/// A requirement check returning null when it holds, or a failure.
typedef ConformanceCheck = Future<String?> Function(
  EpubPublication book,
  EpubRenderSession session,
  HttpClient client,
);

String? _expect(bool condition, String failure) => condition ? null : failure;

Future<int> _status(HttpClient client, Uri url) async {
  final request = await client.getUrl(url);
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}

Future<String?> _imageLoads(
  EpubPublication book,
  EpubRenderSession session,
  HttpClient client, {
  int expected = HttpStatus.ok,
}) async {
  final chapter = await session.prepare(book.readingOrder.first);
  final source = RegExp(r'<img[^>]*\ssrc="([^"]+)"').firstMatch(chapter.html)?.group(1);
  if (source == null) return 'no image in prepared chapter';
  final status = await _status(client, chapter.url.resolve(source));
  return _expect(status == expected, 'image $source returned $status');
}

String? _direction(EpubPublication book, String? expected) {
  final actual = book.metadata.titles.first.direction;
  return _expect(actual == expected, 'title direction $actual, expected $expected');
}

Future<String?> _fontSignature(EpubPublication book, {required bool valid}) async {
  final href = book.encryption.keys.single;
  final bytes = await book.resource(Link(href: href)).read(start: 0, end: 4);
  final signature = String.fromCharCodes(bytes);
  final isFont =
      (bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0) ||
      signature == 'true' ||
      signature == 'OTTO';
  return _expect(isFont == valid, 'font signature $bytes');
}

/// Requirements asserted for W3C tests, keyed by test identifier.
final conformanceChecks = <String, ConformanceCheck>{
  'ocf-package_multiple': (book, _, _) async => _expect(
    book.links.first.href == 'FOO/BAR/package.opf',
    'used ${book.links.first.href}',
  ),
  'ocf-metainf-manifest': (book, _, _) async => _expect(
    book.readingOrder.length == 1,
    'reading order ${book.readingOrder.length}',
  ),
  'pub-xml-non-validating_comment': (book, _, _) async => _expect(
    !book.readingOrder.any((link) => link.href.endsWith('nav.xhtml')),
    'commented itemref was used',
  ),
  'pkg-spine-duplicate-item-rendering': (book, _, _) async => _expect(
    book.readingOrder.where((link) => link.href.endsWith('content_002.xhtml')).length >
        1,
    'duplicates were dropped',
  ),
  'pkg-meta-whitespace': (book, _, _) async => _expect(
    book.metadata.authors.single.name == 'Dave Cramer',
    'creator "${book.metadata.authors.single.name}"',
  ),
  'pkg-creator-order': (book, _, _) async => _expect(
    book.metadata.authors.map((author) => author.name).join(', ') ==
        'Dave Cramer, Wendy Reid, Dan Lazin, Ivan Herman, Brady Duga',
    'creators ${book.metadata.authors.map((author) => author.name)}',
  ),
  'pkg-title-order': (book, _, _) async =>
      _expect(book.metadata.title == 'pkg-title-order', 'title ${book.metadata.title}'),
  'pkg-linked-records': (book, _, _) async => _expect(
    book.metadata.title == 'Package metadata title!',
    'title ${book.metadata.title}',
  ),
  'pkg-manifest-unlisted-resource': (book, session, client) =>
      _imageLoads(book, session, client, expected: HttpStatus.notFound),
  'ocf-url_link-relative': _imageLoads,
  'ocf-url_link-leaking-relative': _imageLoads,
  'ocf-url_link-path-absolute': _imageLoads,
  'pub-file-urls': (book, session, _) async {
    final chapter = await session.prepare(book.readingOrder.first);
    // The test explains its URLs in text; only active references matter.
    final active = RegExp(r'<iframe|(src|href|data)="\s*file:', caseSensitive: false);
    return _expect(!active.hasMatch(chapter.html), 'file URL reference remains');
  },
  'pub-foreign_image': (book, session, client) async {
    final chapter = await session.prepare(book.readingOrder.first);
    final request = await client.getUrl(chapter.url.resolve('p009-star.psd'));
    final response = await request.close();
    await response.drain<void>();
    final type = response.headers.contentType?.mimeType;
    return _expect(type == 'image/png', 'served $type');
  },
  for (final id in [
    'pub-foreign_json-spine',
    'pub-foreign_xml-spine',
    'pub-foreign_xml-suffix-spine',
  ])
    id: (book, session, _) async {
      final url = session.urlFor(book.readingOrder.first);
      return _expect(url.path.endsWith('.xhtml'), 'renders ${url.path}');
    },
  'lay-pp-spine-overrides_image-spine-reflow': (book, session, _) async {
    final chapter = await session.prepare(book.readingOrder[1]);
    return _expect(
      chapter.url.path.endsWith('page_002.xhtml') &&
          !chapter.html.contains('column-width'),
      'renders ${chapter.url.path}',
    );
  },
  for (final id in ['nav-non-text_img', 'nav-non-text_img_title'])
    id: (book, _, _) async => _expect(
      book.tableOfContents.any(
        (link) => link.title == 'Description of the Abbey of Sénanque',
      ),
      'labels ${book.tableOfContents.map((link) => link.title)}',
    ),
  'pkg-dir_rtl-root-unset': (book, _, _) async => _direction(book, 'rtl'),
  'pkg-dir_rtl-root-ltr': (book, _, _) async => _direction(book, 'rtl'),
  'pkg-dir_unset-root-rtl': (book, _, _) async => _direction(book, 'rtl'),
  'pkg-dir_unset-root-unset': (book, _, _) async => _direction(book, null),
  'pkg-dir-auto_root-rtl': (book, _, _) async => _direction(book, 'auto'),
  'pkg-dir-auto_root-unset': (book, _, _) async => _direction(book, 'auto'),
  'pkg-dir_creator-rtl': (book, _, _) async => _expect(
    book.metadata.authors.first.direction == 'rtl',
    'creator direction ${book.metadata.authors.first.direction}',
  ),
  'pkg-version-backward': (book, _, _) async =>
      _expect(book.readingOrder.isNotEmpty, 'no reading order'),
  'ocf-font_obfuscation': (book, _, _) => _fontSignature(book, valid: true),
  'ocf-font_obfuscation_bis': (book, _, _) => _fontSignature(book, valid: false),
};
