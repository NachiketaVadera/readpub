# readpub

An independent pure-Dart EPUB toolkit inspired by Readium. Opens EPUB 2 and EPUB 3
into immutable metadata, reading-order links, resource links, and navigation trees,
and provides persistent locators, EPUB CFI, reading text, positions and search.
It requires Dart 3.13 or later and runs on Dart VM and Flutter host runtimes
without Flutter, FFI, or native bindings.

## Installation

Until published, use a local path dependency:

```yaml
dependencies:
  readpub:
    path: /path/to/readpub/packages/readpub
```

## Opening and reading an EPUB

```dart
import 'package:readpub/readpub.dart';

Future<void> readBook(String path) async {
  final book = await EpubPublication.open(FileAsset(path));
  try {
    print(book.metadata.title);
    print(book.metadata.authors.map((author) => author.name).join(', '));
    for (final chapter in book.readingOrder) {
      print('${chapter.href}: ${chapter.type}');
    }
    final html = await book.resource(book.readingOrder.first).readAsString();
    print(html);
    for (final item in book.tableOfContents) {
      print('${item.title}: ${item.href} (${item.children.length} children)');
    }
    for (final warning in book.warnings) {
      print('${warning.code}: ${warning.message}');
    }
  } finally {
    await book.close();
  }
}
```

Use `MemoryAsset(bytes)` for in-memory input. `book.get(encodedHref)` performs
nullable manifest lookup; query and fragment do not change the archive bytes.
`book.resource(link)` returns a lazy resource with `read`, `readAsString`,
`length`, and `mediaType`. UTF-8 is the default text encoding; pass an explicit
`Encoding` for legacy resource text. Package XML supports UTF-8 and UTF-16.
Resources must not outlive the publication. Reads use half-open byte ranges.

## Parsed features

- OCF container, OPF manifest and spine, linear/non-linear content, fallback
  relationships, bindings, nested collections, and cover resources.
- EPUB 3 metadata refinements, contributors/roles, dates, subjects, accessibility,
  duration, series, rendition layout/orientation/spread and reading progression.
  Raw metadata records preserve unknown values and refinements.
- EPUB 3 XHTML navigation, EPUB 2 NCX fallback, legacy guide landmarks, page lists
  and nested navigation. A structural navigation label uses an empty href.
- Namespaced XML, inherited `xml:base`, encoded paths, Unicode, query and fragment.
- IDPF and Adobe font deobfuscation, including range reads. Encryption declarations
  remain inspectable; unsupported algorithms fail when their resources are read.

`Publication`, `Metadata`, `Link`, and contributor/collection values are independent
of EPUB XML. Value models defensively copy collections, support structural equality,
and expose `toJson()`; this serialization is not a Readium Web Publication manifest.

Run the example:

```sh
dart run example/read_epub.dart test/fixtures/epub/epub3-rich.epub
```

## Locations, positions and search

`ReadingServices` derives reading text, locators, positions and search from the
publication without measuring pixels. Locators serialize to JSON and restore
from their CFI, surrounding text, fragments or progression, whichever still
matches the content.

```dart
import 'dart:convert';

final services = ReadingServices(book);
final positions = await services.positions(); // Cache positions.toJson().

final locator = await services.locatorForProgression(book.readingOrder.first, 0.4);
final json = jsonEncode(locator.toJson()); // Persist with the book identifier.

final restored = await services.resolve(Locator.fromJson(jsonDecode(json)));
print('${restored?.match}: ${restored?.cfi}'); // e.g. epubcfi(/6/2!/4/10/1:42)

await for (final hit in services.search('lantern')) {
  print('${hit.locator.title}: ${hit.locator.text.highlight} at ${hit.cfi}');
}
```

`EpubCfi` parses, serializes, compares and builds EPUB CFI 1.1 points and
ranges. `DocumentText` maps reading text to content-document CFIs in both
directions. `SearchService` lets an application substitute its own index. See
[reading services](../../docs/READING.md).

```sh
dart run example/reading_services.dart test/fixtures/epub/reading.epub whale
```

## Rendering in a browser or WebView

`EpubRenderSession` serves the book from an ephemeral loopback origin. The
browser handles XHTML/HTML layout and author CSS; the session supplies styles,
images, media and deobfuscated fonts from publication resources. The contents
page lists the reading order and TOC. Only the current chapter is prepared.

```dart
import 'dart:io';
import 'package:readpub/readpub.dart';

final book = await EpubPublication.open(FileAsset('/books/book.epub'));
final render = await EpubRenderSession.start(
  book,
  settings: ReaderSettings(
    flow: ReaderFlow.scroll,
    theme: ReaderTheme.sepia,
    fontScale: 1.2,
  ),
);
try {
  print(render.indexUrl); // Load this URL in a browser or WebView.
  print(render.urlFor(book.readingOrder.first));
  await ProcessSignal.sigint.watch().first; // Keep serving until Ctrl+C.
} finally {
  await render.close();
  await book.close();
}
```

For a runnable local preview:

```sh
dart run example/serve_epub.dart test/fixtures/epub/render-assets.epub
```

The server binds only to `127.0.0.1`, uses an unpredictable path per session,
blocks scripts and remote fetches through browser policy, and handles byte ranges
for media/fonts. Prepared chapters keep the element structure that CFIs count, so
locations computed in the browser match the reading services. The optional
`readerLocationScript` can be injected by a host to map selections and the
visible position to CFIs and to navigate to them. Hosts should otherwise disable
JavaScript in WebViews and decide how to handle outbound links. Reader settings
can be changed with `updateSettings` and a page reload. See
[rendering](../../docs/RENDERING.md) for behavior and limits.

## Flutter reader

[`readpub_reader`](../readpub_reader/README.md) is a Flutter
package that displays the render session in a WebView on iOS, Android and
macOS. `ReaderController` handles paging, navigation, settings, selection and
persistable locations; `ReaderView` handles taps, swipes and keys. Its example
app reads a bundled sample book, and its integration tests pass on the iOS
simulator and an Android emulator.

## Safety and scope

ZIP entry counts, allocation, decompression ratios, CRC, and paths are checked.
XML byte/depth/element and navigation limits are configurable using
`EpubParserOptions`. Internal DTD subsets are forbidden; external DTDs are never
fetched. Recoverable metadata/navigation defects produce warnings. Unsafe paths,
limit violations and ambiguous package structure fail explicitly.

Resources stay lazy. Stored members are verified once and then read by range;
compressed ranges require full entry decompression. Input must remain unchanged
during use. CPU-heavy work can block the calling
isolate; applications can move parsing into their own isolate. No remote network requests or EPUB script execution occur. HTTP(S) references are retained but not fetched.

Supported archives are single-disk ZIP32 with stored or Deflate entries. ZIP64,
ZIP encryption, alternate-rendition selection and SMIL timeline interpretation
are not implemented. The renderer uses browser layout; native page controls,
exact pagination measurement and annotation rendering remain application
responsibilities. This is not a complete EPUB conformance claim. See
[compatibility](../../docs/COMPATIBILITY.md) for the precise boundaries.

## Development

```sh
dart pub get
dart analyze --fatal-infos
dart test
dart format --output=none --set-exit-if-changed .
```

See [architecture](../../docs/ARCHITECTURE.md), [decisions](../../docs/adr),
[references](../../docs/REFERENCES.md), [tests](../../docs/TESTING.md),
[performance](../../docs/PERFORMANCE.md) and
[dependencies](../../docs/DEPENDENCIES.md).

## License

BSD 3-Clause. See [LICENSE](LICENSE) and [ATTRIBUTION](ATTRIBUTION.md).
This project is not affiliated with or endorsed by the Readium Foundation.
