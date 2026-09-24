# Reading services

`ReadingServices` turns an open publication into reading text, persistent
locators, publication positions and search results. It is pure Dart, does not
depend on a renderer and never measures pixels. Every service derives from
`DocumentText`, the normalized text model of one content document.

```dart
import 'dart:convert';
import 'package:readpub/readpub.dart';

Future<void> read(String path, String? savedLocator) async {
  final book = await EpubPublication.open(FileAsset(path));
  final services = ReadingServices(book);
  try {
    final positions = await services.positions();
    final positionsCache = jsonEncode(positions.toJson()); // Store per book.

    final chapter = book.readingOrder.first;
    final locator = await services.locatorForProgression(chapter, 0.4);
    final saved = savedLocator ?? jsonEncode(locator.toJson());

    final restored = await services.resolve(Locator.fromJson(jsonDecode(saved)));
    print('${restored?.match} ${restored?.contentCfi} ${positionsCache.length}');

    await for (final hit in services.search('lantern')) {
      print('${hit.locator.title}: ${hit.locator.text.highlight} ${hit.cfi}');
    }
  } finally {
    await book.close();
  }
}
```

The caller owns the publication. Services fail with `ResourceException` after
it is closed. Parsed documents are kept in a small least-recently-used cache
(`cacheSize`, default 8); failures are not cached.

## Document text

`services.documentText(link)` returns `DocumentText` for XHTML, HTML and SVG
resources and null for other media types. A reading-order item that a browser
cannot display, or that is missing, is represented by its manifest fallback, as
the render session displays it; locators, CFIs, positions and search then refer
to that fallback document. Text is extracted as a browser shows
it without author CSS: whitespace collapses inside blocks, `br` becomes a line
feed, `pre` keeps whitespace and blocks are separated by one line feed. The
head, scripts, styles, templates, ruby annotations (`rt`, `rp`), media and
embedded-content fallbacks, SVG descriptive elements and `hidden` subtrees are
excluded. CSS visibility and generated content are not evaluated.

`blocks` lists `TextBlock` values with their `kind` (paragraph, heading, list
item, preformatted, table cell or caption), heading level, list and quotation
depth and language. Offsets are UTF-16 code units in `text`.

Every source character keeps its element path and character-data chunk:

- `cfiAt(offset)` and `cfiForRange(start, end)` produce content-document CFIs,
  with ID assertions on element steps.
- `resolveCfi(cfi)` returns a `CfiTextRange` and reports whether the CFI was
  `exact`, `corrected` by ID or text assertions, or `approximate`. It returns
  null when an assertion fails and cannot be corrected.
- `offsetOfId(id)` and `textAround(start, end)` support fragments and context.

`DocumentText.parse` and `DocumentText.decode` parse documents directly, within
`ContentLimits` (8 MB, 100,000 elements and depth 128 by default).

## Locators

`Locator` is an immutable, JSON-serializable location with an href, media type,
title, `Locations` and `LocatorText`. The href never contains a fragment.
`locations.partialCfi` is a content-document CFI point relative to the
resource's root element. A range is its start point plus `text.highlight`.
Store the publication identifier next to each locator. See ADR 0007 for the
persistence and versioning policy.

| Method | Use |
|---|---|
| `locatorFromLink(link)` | Table of contents and landmark links, without reading content |
| `locatorForProgression(link, p)` | A renderer's scroll or page progression |
| `locatorForCfi(cfi)` | A publication CFI, such as `epubcfi(/6/4[ch1]!/4/2/1:3)` |
| `locatorForCfi(cfi, link: link)` | A content-document CFI or selection from a renderer |
| `locatorForTextRange(link, start, end)` | A hit from an application's own search index |
| `publicationCfi(link, contentCfi)` | Export a location as a standard publication CFI |

Locators include the nearest table-of-contents title, resource progression,
surrounding text and the partial CFI. Once `positions()` has completed they also
include `position` and `totalProgression`. Point locators are placed on the
canonical offset of their CFI, so a point between blocks carries consistent
text context.

## Restoring locations

`resolve(locator)` returns a `LocatorResolution` with the resource link,
reading-order index, text offsets, a navigable `contentCfi`, the publication
`cfi` and the `match` that determined it. Representations are tried in order:

1. The partial CFI, accepted when it resolves and agrees with the stored text.
2. The stored text (`before`, `highlight`, `after`) nearest to the CFI,
   progression or position estimate.
3. A partial CFI that resolved but disagreed with edited text.
4. Fragment identifiers.
5. Progression, then position.
6. The start of the resource.

`resolution.locator` is refreshed with the current CFI, text and positions;
store it to replace a corrected locator. Resolution returns null only when the
href is not a resource of the publication.

## Positions

`positions()` computes deterministic positions once per `ReadingServices`: one
per 1,024 code units of reading text in each reflowable reading-order resource
(`charactersPerPosition`), and one for each fixed-layout, text-free, non-text or
unreadable resource. Non-linear resources have none. `PublicationPositions`
provides the locators, per-resource lists, `positionAt`, `totalProgressionAt`
and the hrefs of unreadable documents. Positions depend on the algorithm
version and settings; cache them with `toJson()` and pass them back with
`ReadingServices(book, positions: PublicationPositions.fromJson(json))`, which
validates them against the reading order.

## Search

`search(query, options: ...)` is a lazy stream over reading-order documents,
one at a time. Cancel the subscription to stop. `SearchOptions` controls case
and diacritic sensitivity, whole-word matching, the result limit (1,000 by
default), context length and whether malformed documents are skipped. Matching
folds whitespace, soft hyphens and zero-width spaces. Matches never cross text
blocks. Each `SearchResult` carries a locator with the highlight and context,
its reading-order index and the publication CFI range.

`SearchService` is an interface. An application can build a persistent index
from `documentText` blocks and implement `SearchService` itself, converting
index hits with `locatorForTextRange`. The core adds no database.

## Renderer integration

Renderers exchange content-document CFIs with these services. See
[rendering](RENDERING.md#locations-and-selections) for the contract and the
optional `readerLocationScript` for browsers and WebViews.
