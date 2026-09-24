import 'dart:convert';
import 'dart:io';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

Future<EpubPublication> fixture(String name) =>
    EpubPublication.open(FileAsset('test/fixtures/epub/$name.epub'));

Future<(HttpClientResponse, List<int>)> fetch(
  HttpClient client,
  Uri url, {
  String? range,
  String method = 'GET',
}) async {
  final request = await client.openUrl(method, url);
  if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
  final response = await request.close();
  final bytes = await response.fold<List<int>>(
    <int>[],
    (result, chunk) => result..addAll(chunk),
  );
  return (response, bytes);
}

void main() {
  test('serves prepared XHTML and unmodified relative CSS and images', () async {
    final book = await fixture('render-assets');
    final session = await EpubRenderSession.start(book);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await session.close();
      await book.close();
    });
    final index = await fetch(client, session.indexUrl);
    expect(index.$1.statusCode, HttpStatus.ok);
    expect(utf8.decode(index.$2), contains('Reading order'));
    final chapter = book.readingOrder.single;
    final url = session.urlFor(chapter);
    final (response, bytes) = await fetch(client, url);
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType?.mimeType, 'application/xhtml+xml');
    expect(
      response.headers.value('Content-Security-Policy'),
      contains("script-src 'none'"),
    );
    expect(response.headers.value('X-Content-Type-Options'), 'nosniff');
    final html = utf8.decode(bytes);
    expect(html, contains('Render me'));
    expect(html, contains('data-readpub="reader"'));
    expect(html, contains('Styles/book.css'));
    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('<base')));
    expect(html, isNot(contains('onload=')));
    final css = await fetch(client, url.resolve('../Styles/book.css'));
    expect(css.$1.statusCode, HttpStatus.ok);
    expect(utf8.decode(css.$2), contains('background-image'));
    final image = await fetch(client, url.resolve('../Images/cover.png'));
    expect(image.$1.statusCode, HttpStatus.ok);
    expect(image.$2, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    final head = await fetch(client, url, method: 'HEAD');
    expect(head.$1.statusCode, HttpStatus.ok);
    expect(head.$1.contentLength, bytes.length);
    expect(head.$2, isEmpty);
  });

  test(
    'settings change the next prepared chapter and fixed layout is preserved',
    () async {
      final book = await fixture('epub3-rich');
      final session = await EpubRenderSession.start(
        book,
        settings: ReaderSettings(flow: ReaderFlow.paged, theme: ReaderTheme.dark),
      );
      addTearDown(() async {
        await session.close();
        await book.close();
      });
      final first = await session.prepare(book.readingOrder.single);
      expect(first.html, contains('height: 100vh'));
      expect(first.html, isNot(contains('column-width:')));
      session.updateSettings(ReaderSettings(theme: ReaderTheme.sepia));
      final second = await session.prepare(book.readingOrder.single);
      expect(second.html, contains('#f4ecd8'));
      expect(first.html, isNot(second.html));
      expect(() => ReaderSettings(fontScale: 10), throwsArgumentError);
      expect(() => ReaderSettings(margin: double.nan), throwsArgumentError);
    },
  );

  test(
    'reflowable paged mode injects columns and preserves navigation fragments',
    () async {
      final book = await fixture('render-assets');
      final session = await EpubRenderSession.start(
        book,
        settings: ReaderSettings(flow: ReaderFlow.paged, fontScale: 1.2),
      );
      addTearDown(() async {
        await session.close();
        await book.close();
      });
      final chapter = await session.prepare(book.readingOrder.single);
      expect(chapter.html, contains('column-width:'));
      expect(chapter.html, contains('120.0%'));
      expect(
        session
            .urlFor(Link(href: '${book.readingOrder.single.href}?x=1#start'))
            .fragment,
        'start',
      );
    },
  );

  test('spine rendition override selects reflowable styling', () async {
    final book = await fixture('render-override');
    final session = await EpubRenderSession.start(
      book,
      settings: ReaderSettings(flow: ReaderFlow.paged),
    );
    addTearDown(() async {
      await session.close();
      await book.close();
    });
    expect(book.metadata.layout, 'fixed');
    expect(book.readingOrder.single.properties['layout'], 'reflowable');
    final chapter = await session.prepare(book.readingOrder.single);
    expect(chapter.html, contains('column-width:'));
  });

  test('legacy HTML is repaired and given UTF-8 and reader styling', () async {
    final book = await fixture('render-html');
    final session = await EpubRenderSession.start(book);
    addTearDown(() async {
      await session.close();
      await book.close();
    });
    final chapter = await session.prepare(book.readingOrder.single);
    expect(chapter.mediaType, 'text/html');
    expect(chapter.html, contains('Second &amp; third — here'));
    expect(chapter.html, isNot(contains('<script')));
    expect(chapter.html, isNot(contains('<base')));
    expect(chapter.html, isNot(contains('http-equiv')));
    expect(chapter.html, isNot(contains('onload=')));
    expect(chapter.html, contains('charset="utf-8"'));
    expect(chapter.html, contains('data-readpub="reader"'));
  });

  test('UTF-16 XHTML becomes UTF-8 without a stale declaration', () async {
    final book = await fixture('render-utf16');
    final session = await EpubRenderSession.start(book);
    addTearDown(() async {
      await session.close();
      await book.close();
    });
    final chapter = await session.prepare(book.readingOrder.single);
    expect(chapter.html, contains('Café 雪'));
    expect(chapter.html, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
  });

  test(
    'preparation neutralizes active content without changing CFI structure',
    () async {
      final book = await fixture('render-structure');
      final session = await EpubRenderSession.start(book);
      addTearDown(() async {
        await session.close();
        await book.close();
      });
      for (final link in book.readingOrder) {
        final original = DocumentText.decode(
          await book.resource(link).read(),
          mediaType: link.type!,
        );
        final prepared = await session.prepare(link);
        final served = DocumentText.parse(prepared.html, mediaType: link.type!);
        expect(served.text, original.text, reason: link.href);
        expect(original.text, isNotEmpty);
        for (var offset = 0; offset <= original.length; offset++) {
          expect(
            served.cfiAt(offset),
            original.cfiAt(offset),
            reason: '${link.href} at $offset',
          );
        }
        expect(prepared.html, isNot(contains('<script')));
        expect(prepared.html, isNot(contains('<iframe')));
        expect(prepared.html, isNot(contains('onclick')));
        expect(prepared.html, contains('data-readpub="reader"'));
      }
      final chapter = await session.prepare(book.readingOrder.first);
      expect(chapter.html, contains('One\u00a0\u2014 two'));
      expect(chapter.html, isNot(contains('nbsp')));
      expect(
        chapter.html,
        contains('<template data-readpub-removed="iframe" id="frame">'),
      );
      expect(
        chapter.html,
        contains(
          '<template xmlns="http://www.w3.org/1999/xhtml" '
          'data-readpub-removed="script"',
        ),
      );
      final headless = await session.prepare(book.readingOrder[1]);
      expect(headless.html, isNot(contains('<head')));
      expect(headless.html, contains('</body><style'));
      final legacy = await session.prepare(book.readingOrder[2]);
      expect(legacy.html, contains('\u201cq\u201d'));
      expect(legacy.html, contains('charset=utf-8'));
      expect(legacy.html, isNot(contains('windows-1252')));
    },
  );

  test('renders spine and content fallbacks for unsupported resources', () async {
    final book = await fixture('fallbacks');
    final session = await EpubRenderSession.start(book);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await session.close();
      await book.close();
    });
    expect(
      session.urlFor(book.readingOrder[0]).path,
      endsWith('/OEBPS/Text/data.xhtml'),
    );
    final plate = await session.prepare(book.readingOrder[1]);
    expect(plate.url.path, endsWith('/OEBPS/Text/plate.xhtml'));
    expect(plate.html, contains('overflow: hidden'), reason: 'spine layout override');
    expect(plate.html, isNot(contains('column-width')));
    final json = await fetch(client, session.baseUrl.resolve('OEBPS/Text/data.json'));
    expect(utf8.decode(json.$2), contains('Data fallback text'));
    final image = await fetch(client, session.baseUrl.resolve('OEBPS/Images/art.psd'));
    expect(image.$1.headers.contentType?.mimeType, 'image/png');
    expect(image.$2, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    final index = await fetch(client, session.indexUrl);
    expect(utf8.decode(index.$2), contains('OEBPS/Text/data.xhtml'));
  });

  test('content URLs leaving the container resolve at its root', () async {
    final book = await fixture('render-urls');
    final session = await EpubRenderSession.start(book);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await session.close();
      await book.close();
    });
    final chapter = await session.prepare(book.readingOrder.single);
    expect(chapter.html, contains('id="absolute" src="../../media/pic.png"'));
    expect(chapter.html, contains('id="leaking" src="../../media/pic.png"'));
    expect(chapter.html, contains('id="normal" src="../../media/pic.png"'));
    expect(chapter.html, contains('href="../../OEBPS/Text/chapter%20one.xhtml#start"'));
    final image = await fetch(client, chapter.url.resolve('../../media/pic.png'));
    expect(image.$1.statusCode, HttpStatus.ok);
    expect(image.$2, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  });

  test('font deobfuscation and HTTP ranges use publication resource access', () async {
    final book = await fixture('font-idpf');
    final session = await EpubRenderSession.start(book);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await session.close();
      await book.close();
    });
    final font = book.resources.singleWhere((link) => link.href.endsWith('font.otf'));
    final url = session.urlFor(font);
    final (response, bytes) = await fetch(client, url, range: 'bytes=1000-1099');
    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.value('Content-Range'), 'bytes 1000-1099/1300');
    expect(bytes, List.generate(100, (index) => (index + 1000) % 251));
    final suffix = await fetch(client, url, range: 'bytes=-10');
    expect(suffix.$2, List.generate(10, (index) => (index + 1290) % 251));
    final unsatisfiable = await fetch(client, url, range: 'bytes=1400-1500');
    expect(unsatisfiable.$1.statusCode, HttpStatus.requestedRangeNotSatisfiable);
  });

  test(
    'session denies unknown paths and closes independently of publication',
    () async {
      final book = await fixture('render-assets');
      final session = await EpubRenderSession.start(book);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await session.close();
        await book.close();
      });
      final missing = await fetch(client, session.baseUrl.resolve('missing.xhtml'));
      expect(missing.$1.statusCode, HttpStatus.notFound);
      final wrongToken = await fetch(
        client,
        session.baseUrl.resolve('/wrong/OEBPS/package.opf'),
      );
      expect(wrongToken.$1.statusCode, HttpStatus.notFound);
      expect(
        () => session.urlFor(Link(href: 'https://example.invalid/image.png')),
        throwsA(isA<ResourceException>()),
      );
      await session.close();
      expect(session.isClosed, isTrue);
      expect(() => session.urlFor(book.readingOrder.single), throwsStateError);
      expect(await book.resource(book.readingOrder.single).read(), isNotEmpty);
    },
  );
}
