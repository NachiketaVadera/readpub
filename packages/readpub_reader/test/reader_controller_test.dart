import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:readpub/readpub.dart';
import 'package:readpub_reader/readpub_reader.dart';

/// A scripted [ReaderSurface] that records commands and answers evaluations.
final class FakeSurface implements ReaderSurface {
  final List<Uri> loads = [];
  int reloads = 0;
  final List<String> runs = [];
  final List<String> evaluations = [];
  Object? Function(String expression) evaluator = (_) => null;
  void Function(String message)? _onMessage;
  void Function(Uri url)? _onPageFinished;
  bool Function(Uri url)? _onNavigationRequest;

  @override
  set onMessage(void Function(String message)? callback) =>
      _onMessage = callback;

  @override
  set onPageFinished(void Function(Uri url)? callback) =>
      _onPageFinished = callback;

  @override
  set onNavigationRequest(bool Function(Uri url)? callback) =>
      _onNavigationRequest = callback;

  @override
  Future<void> load(Uri url) async => loads.add(url);

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<void> run(String script) async => runs.add(script);

  @override
  Future<Object?> evaluate(String expression) async {
    evaluations.add(expression);
    return evaluator(expression);
  }

  @override
  Future<void> setBackgroundColor(Color color) async {}

  void finish([Uri? url]) => _onPageFinished?.call(url ?? loads.last);
  void post(Map<String, Object?> message) =>
      _onMessage?.call(jsonEncode(message));
  bool navigate(Uri url) => _onNavigationRequest?.call(url) ?? false;
}

Map<String, Object?> state(String cfi, {int page = 0, int pageCount = 3}) => {
  'cfi': cfi,
  'progression': 0.0,
  'page': page,
  'pageCount': pageCount,
};

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'condition not reached');
}

Future<(EpubPublication, ReaderController, FakeSurface)> open({
  String fixture = 'reading',
  Locator? initialLocator,
  void Function(Uri url)? onExternalLink,
}) async {
  final book = await EpubPublication.open(
    FileAsset('../readpub/test/fixtures/epub/$fixture.epub'),
  );
  final surface = FakeSurface()
    ..evaluator = (expression) {
      if (expression.contains('restore') || expression.contains('state()')) {
        return state('/4/2[c1]/1:0');
      }
      return null;
    };
  final controller = await ReaderController.create(
    book,
    surface: surface,
    initialLocator: initialLocator,
    onExternalLink: onExternalLink,
  );
  addTearDown(() async {
    controller.dispose();
    await book.close();
  });
  return (book, controller, surface);
}

const drawPrefix = 'window.readpubDecorations.apply(';

/// The `[group, items]` arguments of the decoration drawings evaluated so far.
List<List<Object?>> drawings(FakeSurface surface) => [
  for (final expression in surface.evaluations)
    if (expression.startsWith(drawPrefix))
      jsonDecode(
        '[${expression.substring(drawPrefix.length, expression.length - 1)}]',
      ) as List<Object?>,
];

Future<Locator> phrase(
  ReaderController controller,
  Link link,
  String value,
) async {
  final text = (await controller.services.documentText(link))!.text;
  final start = text.indexOf(value);
  expect(start, isNonNegative, reason: value);
  return controller.services.locatorForTextRange(
    link,
    start,
    start + value.length,
  );
}

Future<void> ready(ReaderController controller, FakeSurface surface) async {
  surface.finish();
  await until(() => controller.isReady && controller.location != null);
}

void main() {
  test('loads the first chapter and reports a persistable location', () async {
    final (book, controller, surface) = await open();
    expect(surface.loads.single.path, endsWith('/OEBPS/Text/one.xhtml'));
    expect(controller.isReady, isFalse);
    await ready(controller, surface);
    expect(surface.runs, [
      readerLocationScript,
      readerBridgeScript,
      readerDecorationScript,
    ]);
    expect(
      surface.evaluations.single,
      contains('window.readpubReader.restore('),
    );
    final location = controller.location!;
    expect(location.readingOrderIndex, 0);
    expect(location.pageCount, 3);
    expect(location.locator.href, 'OEBPS/Text/one.xhtml');
    expect(location.locator.locations.partialCfi, '/4/2[c1]/1:0');
    expect(location.locator.title, 'Chapter One');
    expect(
      Locator.fromJson(jsonDecode(jsonEncode(location.locator))),
      location.locator,
    );
  });

  test(
    'turns pages and crosses chapter boundaries in both directions',
    () async {
      final (book, controller, surface) = await open();
      await ready(controller, surface);
      surface.evaluator = (expression) =>
          expression.contains('nextPage') ? true : null;
      expect(await controller.nextPage(), isTrue);
      expect(surface.loads, hasLength(1));

      surface.evaluator = (expression) {
        if (expression.contains('Page()')) return false;
        if (expression.contains('restore')) {
          return state('/4/2[c2]/1:0', pageCount: 1);
        }
        return null;
      };
      expect(await controller.nextPage(), isTrue);
      expect(surface.loads.last.path, endsWith('/OEBPS/Text/two.xhtml'));
      surface.finish();
      await until(() => controller.location?.readingOrderIndex == 1);
      expect(controller.location!.locator.title, 'Chapter Two');

      surface.evaluator = (expression) {
        if (expression.contains('Page()')) return false;
        if (expression.contains('restore')) {
          return state('/4/84[p40]/1:0', page: 9, pageCount: 10);
        }
        return null;
      };
      expect(await controller.previousPage(), isTrue);
      expect(surface.loads.last.path, endsWith('/OEBPS/Text/one.xhtml'));
      surface.finish();
      await until(() => controller.location?.readingOrderIndex == 0);
      expect(surface.evaluations.last, contains('"end":true'));
      expect(controller.location!.page, 9);
      expect(await controller.previousChapter(), isFalse);
    },
  );

  test(
    'goes to locators and navigation links within and across chapters',
    () async {
      final (book, controller, surface) = await open();
      await ready(controller, surface);
      final section = book.tableOfContents.first.children.single;
      expect(await controller.goToLink(section), isTrue);
      expect(surface.loads, hasLength(1), reason: 'same chapter');
      expect(surface.evaluations.last, contains('"cfi":"/4/44[s2]/1:0"'));

      final document = (await controller.services.documentText(
        book.readingOrder[1],
      ))!;
      final target = await controller.services.locatorForTextRange(
        book.readingOrder[1],
        document.text.indexOf('Ishmael'),
        document.text.indexOf('Ishmael') + 7,
      );
      surface.evaluator = (expression) => expression.contains('restore')
          ? state('/4/6/1:0', pageCount: 1)
          : null;
      expect(await controller.go(target), isTrue);
      expect(surface.loads.last.path, endsWith('/OEBPS/Text/two.xhtml'));
      surface.finish();
      await until(() => controller.location?.readingOrderIndex == 1);
      expect(surface.evaluations.last, contains('"cfi":"/4/6/1:0"'));
      expect(
        await controller.go(Locator(href: 'missing.xhtml', type: 'text/html')),
        isFalse,
      );
    },
  );

  test('restores the location after settings change the layout', () async {
    final (book, controller, surface) = await open();
    await ready(controller, surface);
    surface.post({'type': 'relocated', ...state('/4/26[p12]/1:9', page: 1)});
    await until(() => controller.location?.page == 1);
    await controller.updateSettings(
      ReaderSettings(fontScale: 1.5, flow: ReaderFlow.paged),
    );
    expect(controller.settings.fontScale, 1.5);
    expect(surface.loads, hasLength(1), reason: 'same document reloads');
    expect(surface.reloads, 1);
    expect(surface.loads.single.hasFragment, isFalse);
    expect(controller.isReady, isFalse);
    surface.finish();
    await until(() => controller.isReady);
    expect(surface.evaluations.last, contains('"cfi":"/4/26[p12]/1:9"'));
  });

  test('reports selections and taps, and maps swipes by progression', () async {
    final (book, controller, surface) = await open();
    await ready(controller, surface);
    final chapter = (await controller.services.documentText(
      book.readingOrder.first,
    ))!;
    final start = chapter.text.indexOf('A café');
    final range = chapter.cfiForRange(start, start + 5).expression;
    surface.post({'type': 'selection', 'cfi': range, 'text': 'A caf'});
    await until(() => controller.selection != null);
    expect(controller.selection!.locator.text.highlight, 'A caf');
    surface.post({'type': 'selection', 'cfi': null, 'text': ''});
    await until(() => controller.selection == null);

    final taps = <double>[];
    controller.onTap = (x, y) => taps.add(x);
    surface.post({'type': 'tap', 'x': 0.9, 'y': 0.5});
    expect(taps, [0.9]);

    surface.evaluator = (expression) =>
        expression.contains('Page()') ? true : null;
    surface.post({'type': 'swipe', 'direction': 'left'});
    await until(() => surface.evaluations.last.contains('nextPage'));
    surface.post({'type': 'key', 'key': 'ArrowLeft'});
    await until(() => surface.evaluations.last.contains('previousPage'));
  });

  test('right-to-left publications mirror swipes and keys', () async {
    final (book, controller, surface) = await open(fixture: 'epub3-rich');
    await ready(controller, surface);
    expect(controller.isRightToLeft, isTrue);
    surface.evaluator = (expression) =>
        expression.contains('Page()') ? true : null;
    surface.post({'type': 'swipe', 'direction': 'left'});
    await until(() => surface.evaluations.last.contains('previousPage'));
    surface.post({'type': 'key', 'key': 'ArrowLeft'});
    await until(() => surface.evaluations.last.contains('nextPage'));
  });

  test(
    'keeps navigation inside the session and reports external links',
    () async {
      final external = <Uri>[];
      final (book, controller, surface) = await open(
        onExternalLink: external.add,
      );
      await ready(controller, surface);
      expect(
        surface.navigate(controller.session.urlFor(book.readingOrder[1])),
        isTrue,
      );
      expect(surface.navigate(Uri.parse('about:blank')), isTrue);
      expect(surface.navigate(Uri.parse('https://example.com/')), isFalse);
      expect(
        surface.navigate(Uri.parse('mailto:someone@example.com')),
        isFalse,
      );
      expect(surface.navigate(Uri.parse('file:///etc/hosts')), isFalse);
      expect(external.map((uri) => uri.scheme), ['https', 'mailto', 'file']);

      // A link followed inside the content loads a non-linear note.
      final notes = book.resources.singleWhere(
        (link) => link.href.endsWith('notes.xhtml'),
      );
      surface.evaluator = (expression) => expression.contains('restore')
          ? state('/4/2[n1]/1:0', pageCount: 1)
          : null;
      surface.finish(controller.session.urlFor(notes));
      await until(() => controller.location?.locator.href == notes.href);
      expect(controller.location!.readingOrderIndex, isNull);
      expect(
        await controller.nextPage(),
        isFalse,
        reason: 'no reading-order neighbor',
      );
    },
  );

  test('disposal stops the session and ignores later events', () async {
    final (book, controller, surface) = await open();
    await ready(controller, surface);
    final url = controller.session.urlFor(book.readingOrder.first);
    controller.dispose();
    expect(controller.session.isClosed, isTrue);
    surface.post({'type': 'relocated', ...state('/4/4[p1]/1:0')});
    expect(() => url, returnsNormally);
    expect(surface.navigate(url), isFalse);
  });

  test(
    'draws the decorations of the displayed resource after each load',
    () async {
      final (book, controller, surface) = await open();
      await ready(controller, surface);
      final cafe = await phrase(controller, book.readingOrder[0], 'A café');
      final ishmael = await phrase(controller, book.readingOrder[1], 'Ishmael');
      await controller.applyDecorations('highlights', [
        ReaderDecoration(id: 'cafe', locator: cafe),
        ReaderDecoration(
          id: 'ishmael',
          locator: ishmael,
          style: const ReaderDecorationStyle.underline(Color(0x80102030)),
        ),
      ]);
      final expected = (await controller.services.resolve(cafe))!.contentCfi!;
      expect(expected.isRange, isTrue);
      expect(drawings(surface), [
        [
          'highlights',
          [
            {
              'id': 'cafe',
              'cfi': expected.expression,
              'style': 'highlight',
              'color': [255, 213, 79, 0.439],
            },
          ],
        ],
      ], reason: 'only the displayed chapter is drawn');

      surface.evaluator = (expression) => expression.contains('restore')
          ? state('/4/6/1:0', pageCount: 1)
          : null;
      await controller.nextChapter();
      final before = surface.evaluations.length;
      surface.finish();
      await until(() => controller.location?.readingOrderIndex == 1);
      final loaded = surface.evaluations.sublist(before);
      expect(loaded.first, startsWith(drawPrefix));
      expect(
        loaded.indexWhere((e) => e.contains('restore')),
        greaterThan(0),
        reason: 'drawn before placing',
      );
      expect(drawings(surface).last, [
        'highlights',
        [
          {
            'id': 'ishmael',
            'cfi': isA<String>(),
            'style': 'underline',
            'color': [16, 32, 48, 0.502],
          },
        ],
      ]);
      expect(controller.decorations('highlights'), hasLength(2));

      await controller.applyDecorations('highlights', const []);
      expect(drawings(surface).last, ['highlights', isEmpty]);
      expect(controller.decorations('highlights'), isEmpty);
      await controller.previousChapter();
      final count = surface.evaluations.length;
      surface.finish();
      await until(() => controller.location?.readingOrderIndex == 0);
      expect(
        surface.evaluations.sublist(count).where((e) => e.contains('apply(')),
        isEmpty,
        reason: 'removed groups are not drawn',
      );
    },
  );

  test(
    'draws decorations applied while a chapter loads once it is ready',
    () async {
      final (book, controller, surface) = await open();
      final cafe = await phrase(controller, book.readingOrder[0], 'A café');
      await controller.applyDecorations('notes', [
        ReaderDecoration(id: '1', locator: cafe),
      ]);
      expect(drawings(surface), isEmpty);
      await ready(controller, surface);
      expect(drawings(surface).single.first, 'notes');
      expect(
        surface.evaluations.indexWhere((e) => e.startsWith(drawPrefix)),
        lessThan(surface.evaluations.indexWhere((e) => e.contains('restore'))),
      );
    },
  );

  test(
    'skips decorations whose text is gone and rejects duplicate ids',
    () async {
      final (book, controller, surface) = await open();
      await ready(controller, surface);
      final cafe = await phrase(controller, book.readingOrder[0], 'A café');
      final changed = Locator.fromJson({
        ...cafe.toJson(),
        'text': {'highlight': 'words from another edition'},
      });
      await controller.applyDecorations('highlights', [
        ReaderDecoration(id: 'gone', locator: changed),
        ReaderDecoration(
          id: 'elsewhere',
          locator: Locator(href: 'OEBPS/Text/missing.xhtml', type: 'text/html'),
        ),
      ]);
      expect(drawings(surface), [
        ['highlights', isEmpty],
      ]);
      expect(
        () => controller.applyDecorations('highlights', [
          ReaderDecoration(id: 'same', locator: cafe),
          ReaderDecoration(id: 'same', locator: cafe),
        ]),
        throwsArgumentError,
      );
    },
  );

  test('reports taps on decorations', () async {
    final (book, controller, surface) = await open();
    await ready(controller, surface);
    final cafe = await phrase(controller, book.readingOrder[0], 'A café');
    final decoration = ReaderDecoration(id: 'cafe', locator: cafe);
    await controller.applyDecorations('highlights', [decoration]);
    final activations = <ReaderDecorationActivation>[];
    final taps = <double>[];
    controller
      ..onDecorationActivated = activations.add
      ..onTap = (x, y) => taps.add(x);
    surface
      ..post({
        'type': 'decorationActivated',
        'group': 'highlights',
        'id': 'cafe',
        'x': 40,
        'y': 60,
        'rect': {'x': 30, 'y': 50, 'width': 100, 'height': 22},
      })
      ..post({
        'type': 'decorationActivated',
        'group': 'highlights',
        'id': 'unknown',
        'x': 1,
        'y': 1,
      });
    expect(activations, hasLength(1));
    final activation = activations.single;
    expect(activation.group, 'highlights');
    expect(activation.decoration, decoration);
    expect(activation.point, const Offset(40, 60));
    expect(activation.rect, const Rect.fromLTWH(30, 50, 100, 22));
    expect(taps, isEmpty);
  });

  test('decodes WebKit and Android JavaScript results alike', () {
    expect(decodeScriptResult('{"page":1}'), {'page': 1});
    expect(decodeScriptResult(jsonEncode('{"page":1}')), {'page': 1});
    expect(decodeScriptResult('true'), isTrue);
    expect(decodeScriptResult(jsonEncode('true')), isTrue);
    expect(decodeScriptResult('null'), isNull);
    expect(decodeScriptResult(jsonEncode('"text"')), 'text');
    expect(decodeScriptResult(3), 3);
  });
}
