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
        home: Scaffold(body: ReaderView(controller: controller)),
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
