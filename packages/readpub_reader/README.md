# readpub_reader

A Flutter EPUB reader built on [readpub](../readpub/README.md). It displays chapters
from readpub's loopback render session in a WebView and turns the reader's
position, pages, selections and navigation into persistable `Locator` values.

It runs on iOS, Android and macOS through the official `webview_flutter`
plugin. The integration tests pass on the iOS simulator (WebKit) and on an
Android emulator (Android System WebView); see
[verification](../../docs/VERIFICATION.md).

## Usage

```dart
import 'package:readpub/readpub.dart';
import 'package:readpub_reader/readpub_reader.dart';

final book = await EpubPublication.open(FileAsset(path));
final controller = await ReaderController.create(
  book,
  settings: ReaderSettings(flow: ReaderFlow.paged),
  initialLocator: savedLocator, // From Locator.fromJson, or null.
  onExternalLink: (url) => askBeforeOpening(url),
);

// In a widget tree:
ReaderView(controller: controller, onCenterTap: toggleToolbars);

// Persist the reading position:
controller.addListener(() {
  final locator = controller.location?.locator;
  if (locator != null) save(jsonEncode(locator.toJson()));
});

// Navigate, turn pages and change settings:
await controller.goToLink(book.tableOfContents.first);
await controller.nextPage();
await controller.updateSettings(ReaderSettings(theme: ReaderTheme.dark));

// When done, dispose the controller before closing the publication:
controller.dispose();
await book.close();
```

`controller.location` reports the first visible character as a locator with a
content-document CFI, text context, title, progression and, once computed,
publication positions. `controller.go(locator)` restores any locator, including
ones saved by earlier versions of a book, through the resolution order of
`ReadingServices.resolve`. `controller.selection` and `selectionLocator()`
return the selected text as a locator whose `text.highlight` is the selection.
`controller.services` exposes search, positions and document text.

`ReaderView` turns pages on taps in the leading and trailing quarter of the
width, on horizontal swipes in paged flow and on arrow and page keys, mirrored
for right-to-left publications. Other taps call `onCenterTap`. The page stays
covered until the loaded chapter is positioned, so readers never see a jump
from the chapter start.

## Platform setup

The reader serves chapters over HTTP on `127.0.0.1`.

- **iOS**: allow local networking in `Info.plist`:

  ```xml
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
  ```

- **Android**: add `<uses-permission android:name="android.permission.INTERNET"/>`
  (loopback sockets require it) and permit cleartext traffic to `127.0.0.1`
  only, with a network security configuration such as the example's
  `res/xml/network_security_config.xml`.
- **macOS**: add the `com.apple.security.network.server` and
  `com.apple.security.network.client` entitlements.

## Security

JavaScript is enabled in the WebView so the host can inject readpub's
`readerLocationScript` and this package's `readerBridgeScript`. Publication
scripts do not run: the render session replaces script elements with inert
placeholders and serves a `script-src 'none'` Content Security Policy.
Navigation is confined to the render session; every other URL, including web,
`mailto:`, `file:` and `data:` links, is refused and reported to
`onExternalLink` so the application can ask for consent. On Android, WebView
file and content access are disabled.

## Scope and limits

- Page turns are immediate, without an animation or page curl.
- Highlights and annotations are not rendered yet; selections and locators
  provide the positions to build them on.
- Fixed-layout pages are shown one per screen with their own viewport; there
  are no synthetic spreads, and no zoom beyond the WebView's defaults.
- Text-to-speech and media-overlay playback are not implemented.
- `ReaderSurface` abstracts the browser, so another WebView plugin can be used
  by implementing it; `ReaderView` requires the default `WebViewReaderSurface`.

## Testing

```sh
flutter test                                   # Controller unit tests.
cd example
flutter test integration_test/reader_test.dart -d <simulator-or-emulator>
```

The integration tests page through chapters, navigate to contents entries and
search results, change themes and font size, reopen saved locators, select
text, follow footnotes and external links, and scroll, asserting where text
appears on screen.
