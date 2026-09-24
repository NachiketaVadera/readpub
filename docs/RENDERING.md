# Browser rendering

The renderer uses a browser engine for EPUB XHTML and HTML layout. The Dart core
prepares content and serves only manifest resources over an ephemeral HTTP server
bound to `127.0.0.1`. It does not create a native UI or implement browser layout.
This design follows [EPUB 3.3 content documents](https://www.w3.org/TR/epub-33/)
and takes conceptual inspiration from [Readium CSS](https://github.com/readium/css).
The bundled reader styles are original, small CSS rules, not a copy of Readium CSS.

## Lifecycle

```dart
import 'dart:io';
import 'package:readpub/readpub.dart';

final publication = await EpubPublication.open(FileAsset(path));
final session = await EpubRenderSession.start(publication);
try {
  final contents = session.indexUrl;
  final chapter = session.urlFor(publication.readingOrder.first);
  // Load either URL in a browser or WebView while this session stays alive.
  print(contents);
  print(chapter);
  await ProcessSignal.sigint.watch().first;
} finally {
  await session.close();
  await publication.close();
}
```

The contents page links to chapters and nested TOC targets. The `urlFor` method
accepts normalized local manifest or navigation links and preserves query and
fragment. When a linked resource cannot be displayed by a browser, or is
missing, it returns the first displayable resource in the manifest fallback
chain, and `prepare` applies the spine item's rendition overrides to it. Requests
for foreign resources, such as a PSD image, receive their first core-media-type
fallback. Relative CSS, images, media and fonts resolve beneath the session
origin. Missing or remote resources are not fetched. The caller owns both the
session and publication and must close both.

`prepare(link)` returns the transformed HTML and its URL if an app needs the
source directly. It checks the declared and actual byte size, then XML element/
depth or legacy HTML node/depth limits, and fails with `ContentException`.
XHTML is parsed namespace-aware, with HTML named character references such as
`&nbsp;` decoded as browsers do for XHTML document types, and emitted as UTF-8.
Legacy HTML uses an HTML5 parser. UTF-8 with a byte order mark, UTF-16 and
common legacy Windows-1252 content are decoded. Publisher text and styles are
retained, with reader styles appended after existing head content. Reflowable
documents also receive a `width=device-width` viewport declaration, without
which mobile WebViews lay pages out at desktop width; fixed-layout documents
keep the author's viewport.

Preparation preserves the element and character-data structure that EPUB CFIs
count, so browser-side locations match the original document (ADR 0010).
`base`, `script`, `iframe`, `object` and `embed` elements are replaced by empty
XHTML `template` placeholders that keep their ID. Refresh `meta` elements lose
only their `http-equiv` and `content` attributes, and inline event handlers and
JavaScript URLs are removed. A document without a head receives reader styles
at the end of its root element. Legacy HTML charset declarations are rewritten
in place, or a declaration is appended. `href`, `src`, `poster` and `data`
URLs that leave the container or start with `/` are rewritten to the relative
URL the EPUB container root URL gives them, because a browser would otherwise
resolve them outside the session path; CSS `url()` values are not rewritten.

## Settings and HTTP behavior

`ReaderSettings` controls light/dark/sepia theme, font scale, line height,
viewport margin and scroll or paged flow. Paged flow uses viewport-width CSS
columns, so its exact geometry depends on the browser. Publication fixed layout
uses viewport sizing instead of column flow; a spine `rendition:layout` override
takes precedence. `updateSettings` applies to subsequent chapter loads, so the
host reloads its current URL to apply a change.

The HTTP server handles GET and HEAD. It supports one `bytes=start-end`, open
or suffix range for non-document resources and returns 416 for invalid ranges.
It reads through `Publication.resource`, so font obfuscation is applied before
bytes reach the browser. A chapter request transforms that chapter only; no
whole-book HTML or image allocation is made.

## Locations and selections

Renderers and the core exchange content-document CFIs: expressions relative to
the root element of the loaded chapter, such as `/4/10[para05]/3:10`, counting
child elements with even indices and character-data chunks with odd indices,
ignoring comments and processing instructions, and counting UTF-16 code units.
Send a CFI together with the chapter link to
`ReadingServices.locatorForCfi(cfi, link: link)` to create a locator; navigate
with `LocatorResolution.contentCfi`, which the core has validated and
corrected. A renderer without script access can report and restore
`progression` instead, with `locatorForProgression` and
`LocatorResolution.locator.locations.progression`. See [reading](READING.md).

`readerLocationScript` is an optional reference implementation. After a chapter
loads, a host can inject it with its WebView's evaluate-JavaScript API. It
defines `window.readpub` with `cfiFromPoint`, `cfiFromRange`, `selectionCfi`,
`rangeFromCfi`, `firstVisibleCfi`, `scrollToCfi`, `progression` and
`scrollToProgression` for both scroll and paged flows. It follows ID assertions
but leaves text assertions and corrections to the Dart services. The session
never serves or executes the script, and the response policy continues to block
publication scripts.

Injecting the script requires script execution by the host. Where a platform
lets the host evaluate scripts while page scripts are disabled, use that
configuration. Otherwise enabling JavaScript relies on the session's
`script-src 'none'` policy and script removal to keep publication scripts
inert; verify on each target platform that host-evaluated scripts run under
that policy. The script was verified against `DocumentText` in a Chromium-based
browser, and through the Flutter reader's integration tests in WebKit on the iOS
simulator and in Android System WebView on an Android emulator (see
VERIFICATION.md). Physical devices remain unverified. The
[Flutter reader package](../packages/readpub_reader/README.md) implements this
contract for iOS, Android and macOS.

## Security and host responsibilities

Each session uses a random 128-bit path token on an ephemeral loopback port.
Responses send a restrictive Content Security Policy and no-sniff/no-referrer
headers. Scripts, remote fetches, frames, forms and objects are blocked. Browser
hosts should disable JavaScript independently unless they inject the location
script as described above, prevent unintended navigation to external sites and
avoid exposing the loopback URL to untrusted recipients.
Only manifest entries can be served. The browser is still responsible for CSS,
SVG and media behavior; the package does not claim to sanitize arbitrary EPUB
content for use under a weaker policy.

This bridge is designed for Dart VM and Flutter host runtimes. It does not run
inside a Dart web build. Native page gestures, exact page count, selection UI,
annotation rendering, publication scripting support and media-overlay playback
remain outside this adapter.
