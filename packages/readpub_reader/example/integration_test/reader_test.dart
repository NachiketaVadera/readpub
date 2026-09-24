import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:readpub/readpub.dart';
import 'package:readpub_reader/readpub_reader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(
    WidgetTester tester,
    bool Function() condition, {
    String reason = 'condition not reached',
  }) async {
    for (var i = 0; i < 150 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    expect(condition(), isTrue, reason: reason);
  }

  Future<(EpubPublication, ReaderController)> start(
    WidgetTester tester, {
    ReaderSettings? settings,
    Locator? initialLocator,
    void Function(Uri url)? onExternalLink,
    VoidCallback? onCenterTap,
  }) async {
    final data = await rootBundle.load('assets/lantern-keeper.epub');
    final book = await EpubPublication.open(
      MemoryAsset(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    );
    final controller = await ReaderController.create(
      book,
      settings: settings,
      initialLocator: initialLocator,
      onExternalLink: onExternalLink,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderView(controller: controller, onCenterTap: onCenterTap),
        ),
      ),
    );
    await settle(
      tester,
      () => controller.isReady && controller.location != null,
    );
    return (book, controller);
  }

  Future<void> finish(
    WidgetTester tester,
    EpubPublication book,
    ReaderController controller,
  ) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await book.close();
  }

  /// Whether any part of the text at a content CFI is inside the viewport.
  Future<bool> visible(ReaderController controller, String cfi) async {
    final result = await controller.surface.evaluate('''JSON.stringify((() => {
      const range = window.readpub.rangeFromCfi(${jsonEncode(cfi)});
      if (!range) return false;
      if (range.collapsed && range.startContainer.nodeType === 3 &&
          range.startOffset < range.startContainer.length) {
        range.setEnd(range.startContainer, range.startOffset + 1);
      }
      return Array.from(range.getClientRects()).some((r) =>
        r.width + r.height > 0 && r.left >= -1 && r.right <= innerWidth + 1 &&
        r.top >= -1 && r.bottom <= innerHeight + 1);
    })())''');
    return result == true;
  }

  Future<int> offset(ReaderController controller, Locator locator) async {
    final text = await controller.services.documentText(
      Link(href: locator.href),
    );
    return text!
        .resolveCfi(EpubCfi.parse(locator.locations.partialCfi!))!
        .start;
  }

  /// A locator for the text from [value] through [through], or [value] alone.
  Future<Locator> phrase(
    ReaderController controller,
    Link link,
    String value, {
    String? through,
  }) async {
    final text = (await controller.services.documentText(link))!.text;
    final start = text.indexOf(value);
    final end = through == null
        ? start + value.length
        : text.indexOf(through, start) + through.length;
    expect(start, isNonNegative, reason: value);
    return controller.services.locatorForTextRange(link, start, end);
  }

  Future<String> rangeOf(ReaderController controller, Locator locator) async =>
      (await controller.services.resolve(locator))!.contentCfi!.expression;

  /// Measures how a drawn decoration covers its text in the viewport, or
  /// returns null if it is not drawn.
  ///
  /// `loose` counts drawn marks whose center is not on the decorated text,
  /// and `uncovered` counts visible decorated characters without a mark.
  Future<Map<String, Object?>?> inspect(
    ReaderController controller,
    String group,
    String id,
    String cfi,
  ) async {
    // Let the page render a frame, as a reader would see it; scroll events
    // that move decorations are dispatched before painting.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final result = await controller.surface.evaluate('''JSON.stringify((() => {
      const host = document.querySelector('readpub-decorations');
      const element = host && host.shadowRoot.querySelector(
        '[data-group=${jsonEncode(group)}][data-id=${jsonEncode(id)}]');
      if (!element) return null;
      const underline = element.getAttribute('data-style') === 'underline';
      const range = window.readpub.rangeFromCfi(${jsonEncode(cfi)});
      const view = (r) => r.right > 1 && r.left < innerWidth - 1 &&
        r.bottom > 1 && r.top < innerHeight - 1;
      const boxes = Array.from(element.children, (c) => c.getBoundingClientRect());
      const shown = boxes.filter(view);
      let loose = 0;
      for (const box of shown) {
        const x = box.left + box.width / 2;
        const y = underline ? box.top - 5 : box.top + box.height / 2;
        const caret = document.caretRangeFromPoint(x, y);
        if (!caret || range.comparePoint(caret.startContainer, caret.startOffset) !== 0) {
          loose++;
        }
      }
      let characters = 0;
      let uncovered = 0;
      const root = range.commonAncestorContainer;
      const walker = document.createTreeWalker(
        root.nodeType === 1 ? root : root.parentNode, 4);
      const probe = document.createRange();
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!range.intersectsNode(node)) continue;
        const from = node === range.startContainer ? range.startOffset : 0;
        const to = node === range.endContainer ? range.endOffset : node.length;
        for (let i = from; i < to; i++) {
          if (/\\s/.test(node.data[i])) continue;
          probe.setStart(node, i);
          probe.setEnd(node, i + 1);
          const r = probe.getClientRects()[0];
          if (!r || !view(r)) continue;
          characters++;
          const x = r.left + r.width / 2;
          const y = r.top + r.height / 2;
          if (!shown.some((b) => x >= b.left - 1 && x <= b.right + 1 && (underline
              ? Math.abs(b.bottom - r.bottom) <= 3
              : y >= b.top - 1 && y <= b.bottom + 1))) {
            uncovered++;
          }
        }
      }
      const first = shown[0];
      return {
        boxes: boxes.length,
        shown: shown.length,
        loose,
        characters,
        uncovered,
        height: Math.max(0, ...shown.map((b) => b.height)),
        center: first ? [first.left + first.width / 2, first.top + first.height / 2] : null,
        color: element.firstElementChild
          ? getComputedStyle(element.firstElementChild).backgroundColor : null,
        opacity: getComputedStyle(element).opacity,
        blend: getComputedStyle(host).mixBlendMode,
      };
    })())''');
    return (result as Map?)?.cast<String, Object?>();
  }

  /// Expects a drawn decoration to cover exactly its visible text.
  Future<Map<String, Object?>> expectDrawn(
    ReaderController controller,
    String group,
    String id,
    String cfi,
  ) async {
    final drawn = await inspect(controller, group, id, cfi);
    expect(drawn, isNotNull, reason: '$id is drawn');
    expect(drawn!['shown'], greaterThan(0), reason: '$id is visible');
    expect(drawn['characters'], greaterThan(0), reason: '$id text is visible');
    expect(drawn['loose'], 0, reason: '$id marks are on its text');
    expect(drawn['uncovered'], 0, reason: '$id text is marked');
    return drawn;
  }

  /// Dispatches a click at a viewport point, as a tap on the page does.
  Future<void> click(ReaderController controller, List<Object?> point) =>
      controller.surface.run('''(() => {
        const [x, y] = ${jsonEncode(point)};
        document.elementFromPoint(x, y).dispatchEvent(new MouseEvent('click',
          { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window }));
      })()''');

  testWidgets('pages through chapters and keeps locations exact', (
    tester,
  ) async {
    final (book, controller) = await start(
      tester,
      settings: ReaderSettings(flow: ReaderFlow.paged),
    );
    expect(controller.location!.readingOrderIndex, 0, reason: 'cover');

    await controller.nextPage();
    await settle(tester, () => controller.location?.readingOrderIndex == 1);
    final first = controller.location!;
    expect(first.page, 0);
    expect(first.pageCount, greaterThan(1), reason: 'chapter one spans pages');
    expect(await offset(controller, first.locator), 0);
    expect(first.locator.title, '1. The Lighthouse at Harrow Point');
    expect(
      await visible(controller, first.locator.locations.partialCfi!),
      isTrue,
    );

    await controller.nextPage();
    await settle(tester, () => controller.location?.page == 1);
    final second = controller.location!;
    expect(await offset(controller, second.locator), greaterThan(0));
    expect(
      await visible(controller, second.locator.locations.partialCfi!),
      isTrue,
    );
    expect(
      await visible(controller, first.locator.locations.partialCfi!),
      isFalse,
    );

    await controller.previousPage();
    await settle(tester, () => controller.location?.page == 0);
    await controller.previousPage();
    await settle(tester, () => controller.location?.readingOrderIndex == 0);

    // Continuing backward from a chapter start lands on the previous end.
    await controller.goToLink(book.tableOfContents[2]);
    await settle(tester, () => controller.location?.readingOrderIndex == 2);
    await controller.previousPage();
    await settle(tester, () => controller.location?.readingOrderIndex == 1);
    final end = controller.location!;
    expect(end.page, end.pageCount - 1);
    await finish(tester, book, controller);
  });

  testWidgets('navigates to contents, search results and back after relayout', (
    tester,
  ) async {
    final (book, controller) = await start(
      tester,
      settings: ReaderSettings(flow: ReaderFlow.paged),
    );
    final section = book.tableOfContents[4].children.single;
    await controller.goToLink(section);
    await settle(tester, () => controller.location?.readingOrderIndex == 4);
    final chapter = (await controller.services.documentText(
      book.readingOrder[4],
    ))!;
    final heading = chapter.cfiAt(chapter.offsetOfId('c4-s')!).expression;
    await settle(tester, () => controller.isReady);
    expect(
      await visible(controller, heading),
      isTrue,
      reason: 'section heading',
    );

    final hit = await controller.services.search('glass fingers').first;
    await controller.go(hit.locator);
    await settle(tester, () => controller.location?.readingOrderIndex == 3);
    final match = hit.locator.locations.partialCfi!;
    expect(await visible(controller, match), isTrue, reason: 'search result');

    await controller.updateSettings(
      ReaderSettings(
        flow: ReaderFlow.paged,
        fontScale: 1.6,
        theme: ReaderTheme.dark,
      ),
    );
    await settle(tester, () => controller.isReady);
    await settle(tester, () => controller.location?.readingOrderIndex == 3);
    final style = await controller.surface.evaluate(
      'JSON.stringify([getComputedStyle(document.documentElement).backgroundColor, '
      'getComputedStyle(document.documentElement).fontSize])',
    );
    expect(style, [
      'rgb(23, 25, 28)',
      isNot('16px'),
    ], reason: 'settings applied');
    final saved = controller.location!.locator;
    expect(
      await offset(controller, saved),
      lessThanOrEqualTo(await offset(controller, hit.locator)),
    );

    // A new reader restores the saved locator to the same page.
    await finish(tester, book, controller);
    final (reopened, restored) = await start(
      tester,
      settings: ReaderSettings(flow: ReaderFlow.paged, fontScale: 1.6),
      initialLocator: Locator.fromJson(jsonDecode(jsonEncode(saved))),
    );
    expect(restored.location!.readingOrderIndex, 3);
    expect(await visible(restored, saved.locations.partialCfi!), isTrue);
    await finish(tester, reopened, restored);
  });

  testWidgets('maps selections and follows footnotes and external links', (
    tester,
  ) async {
    final external = <Uri>[];
    final (book, controller) = await start(
      tester,
      onExternalLink: external.add,
    );
    await controller.nextChapter();
    await controller.nextChapter();
    await settle(tester, () => controller.location?.readingOrderIndex == 2);

    await controller.surface.run('''(() => {
      const paragraph = document.getElementById('c2-1');
      const text = paragraph.firstChild;
      const start = text.data.indexOf('supply boat');
      const range = document.createRange();
      range.setStart(text, start);
      range.setEnd(text, start + 'supply boat'.length);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    })()''');
    await settle(tester, () => controller.selection != null);
    expect(controller.selection!.text, 'supply boat');
    expect(controller.selection!.locator.text.highlight, 'supply boat');
    expect(
      (await controller.selectionLocator())!.text.highlight,
      'supply boat',
    );

    await controller.surface.run("document.getElementById('ref1').click()");
    await settle(
      tester,
      () => controller.location?.locator.href == 'OEBPS/Text/notes.xhtml',
    );
    expect(controller.location!.readingOrderIndex, isNull);
    await controller.surface.run("document.querySelector('a[href]').click()");
    await settle(tester, () => controller.location?.readingOrderIndex == 2);

    await controller.goToLink(book.tableOfContents.last);
    await settle(tester, () => controller.location?.readingOrderIndex == 6);
    await controller.surface.run(
      "document.querySelector('a[href^=\"https\"]').click()",
    );
    await settle(tester, () => external.isNotEmpty);
    expect(external.single.host, 'www.w3.org');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(
      controller.location!.readingOrderIndex,
      6,
      reason: 'stayed in the book',
    );
    await finish(tester, book, controller);
  });

  testWidgets('draws decorations on their text and reports taps on them', (
    tester,
  ) async {
    var centerTaps = 0;
    final (book, controller) = await start(
      tester,
      settings: ReaderSettings(flow: ReaderFlow.paged),
      onCenterTap: () => centerTaps++,
    );
    final activations = <ReaderDecorationActivation>[];
    controller.onDecorationActivated = activations.add;
    await controller.nextChapter();
    await settle(
      tester,
      () => controller.isReady && controller.location?.readingOrderIndex == 1,
    );

    final one = book.readingOrder[1];
    const opening = 'Mara Venn arrived at Harrow Point';
    final openingLocator = await phrase(controller, one, opening);
    final across = await phrase(
      controller,
      one,
      'a second, smaller sunset.',
      through: 'The retiring keeper',
    );
    final harbours = await phrase(
      controller,
      one,
      'dreamed of harbours she had never seen',
    );
    final boat = await phrase(
      controller,
      book.readingOrder[2],
      'The supply boat',
    );
    await controller.applyDecorations('highlights', [
      ReaderDecoration(id: 'opening', locator: openingLocator),
      ReaderDecoration(
        id: 'harbours',
        locator: harbours,
        style: const ReaderDecorationStyle.highlight(Color(0x8066bb6a)),
      ),
      ReaderDecoration(id: 'boat', locator: boat),
    ]);
    await controller.applyDecorations('underlines', [
      ReaderDecoration(
        id: 'across',
        locator: across,
        style: const ReaderDecorationStyle.underline(),
      ),
    ]);

    final first = await expectDrawn(
      controller,
      'highlights',
      'opening',
      await rangeOf(controller, openingLocator),
    );
    expect(first['characters'], opening.replaceAll(' ', '').length);
    expect(first['color'], 'rgb(255, 213, 79)');
    expect(double.parse(first['opacity']! as String), closeTo(0.439, 0.001));
    expect(first['blend'], 'multiply');
    expect(
      await inspect(
        controller,
        'highlights',
        'boat',
        await rangeOf(controller, boat),
      ),
      isNull,
      reason: 'decorations of other chapters are not drawn',
    );

    // A tap on a highlight activates it instead of turning the page.
    final page = controller.location!.page;
    await click(controller, first['center']! as List<Object?>);
    await settle(tester, () => activations.isNotEmpty);
    final activation = activations.single;
    expect(activation.group, 'highlights');
    expect(activation.decoration.id, 'opening');
    expect(activation.rect!.inflate(1).contains(activation.point), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.location!.page, page);
    expect(centerTaps, 0);
    final heading = await controller.surface.evaluate('''JSON.stringify((() => {
      const r = document.getElementById('c1').getBoundingClientRect();
      return [r.left + r.width / 2, r.top + r.height / 2];
    })())''');
    await click(controller, heading! as List<Object?>);
    await settle(tester, () => centerTaps == 1);
    expect(activations, hasLength(1));

    // An underline across two paragraphs marks only their text.
    await controller.go(across);
    await settle(tester, () => controller.isReady);
    final underline = await expectDrawn(
      controller,
      'underlines',
      'across',
      await rangeOf(controller, across),
    );
    expect(underline['height'], lessThanOrEqualTo(3));
    expect(underline['color'], 'rgb(229, 57, 53)');

    // Decorations move with the pages.
    await controller.go(harbours);
    await settle(
      tester,
      () => controller.isReady && (controller.location?.page ?? 0) > 0,
    );
    final harboursRange = await rangeOf(controller, harbours);
    final green = await expectDrawn(
      controller,
      'highlights',
      'harbours',
      harboursRange,
    );
    expect(green['color'], 'rgb(102, 187, 106)');
    final hidden = await inspect(
      controller,
      'highlights',
      'opening',
      await rangeOf(controller, openingLocator),
    );
    expect(hidden!['shown'], 0, reason: 'the first page is out of view');

    // Relayout redraws them; dark pages composite them normally.
    await controller.updateSettings(
      ReaderSettings(
        flow: ReaderFlow.paged,
        fontScale: 1.5,
        theme: ReaderTheme.dark,
      ),
    );
    await settle(tester, () => controller.isReady);
    await controller.go(harbours);
    await settle(tester, () => controller.isReady);
    final dark = await expectDrawn(
      controller,
      'highlights',
      'harbours',
      harboursRange,
    );
    expect(dark['blend'], 'normal');

    await controller.nextChapter();
    await settle(
      tester,
      () => controller.isReady && controller.location?.readingOrderIndex == 2,
    );
    await expectDrawn(
      controller,
      'highlights',
      'boat',
      await rangeOf(controller, boat),
    );
    expect(
      await inspect(controller, 'highlights', 'harbours', harboursRange),
      isNull,
    );

    await controller.applyDecorations('highlights', const []);
    await controller.applyDecorations('underlines', const []);
    expect(
      await controller.surface.evaluate(
        "JSON.stringify(document.querySelector('readpub-decorations') === null)",
      ),
      isTrue,
    );
    await finish(tester, book, controller);
  });

  testWidgets('keeps decorations on their text while scrolling', (
    tester,
  ) async {
    final (book, controller) = await start(
      tester,
      settings: ReaderSettings(flow: ReaderFlow.scroll),
    );
    final activations = <ReaderDecorationActivation>[];
    controller.onDecorationActivated = activations.add;
    await controller.nextChapter();
    await settle(
      tester,
      () => controller.isReady && controller.location?.readingOrderIndex == 1,
    );
    final stairs = await phrase(
      controller,
      book.readingOrder[1],
      'The stairs turned to the left, always to the left',
    );
    await controller.applyDecorations('highlights', [
      ReaderDecoration(id: 'stairs', locator: stairs),
    ]);
    await controller.go(stairs);
    await settle(tester, () => controller.isReady);
    final range = await rangeOf(controller, stairs);
    final before = await expectDrawn(controller, 'highlights', 'stairs', range);

    final scrolled = await controller.surface.evaluate(
      'JSON.stringify((() => { const y = scrollY; scrollBy(0, -60); '
      'return y - scrollY; })())',
    );
    expect(scrolled, greaterThan(0));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = await expectDrawn(controller, 'highlights', 'stairs', range);
    expect(
      (after['center']! as List<Object?>)[1]! as num,
      closeTo(
        ((before['center']! as List<Object?>)[1]! as num) + (scrolled! as num),
        1,
      ),
    );
    await click(controller, after['center']! as List<Object?>);
    await settle(tester, () => activations.isNotEmpty);
    expect(activations.single.decoration.id, 'stairs');
    await finish(tester, book, controller);
  });

  testWidgets('scrolls in scroll flow and reports progress', (tester) async {
    final (book, controller) = await start(
      tester,
      settings: ReaderSettings(flow: ReaderFlow.scroll, fontScale: 1.4),
    );
    await controller.nextChapter();
    await settle(tester, () => controller.location?.readingOrderIndex == 1);
    await settle(tester, () => controller.positions != null);
    final top = controller.location!.locator;
    await controller.nextPage();
    await settle(
      tester,
      () =>
          controller.location!.locator.locations.partialCfi !=
          top.locations.partialCfi,
    );
    final lower = controller.location!.locator;
    expect(controller.location!.pageCount, 1);
    expect(
      await offset(controller, lower),
      greaterThan(await offset(controller, top)),
    );
    expect(lower.locations.position, isNotNull);
    expect(
      lower.locations.totalProgression!,
      greaterThanOrEqualTo(top.locations.totalProgression!),
    );
    await finish(tester, book, controller);
  });
}
