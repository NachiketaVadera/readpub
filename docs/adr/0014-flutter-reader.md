# ADR 0014: A Flutter reader over the render session

Status: accepted and implemented.

The core stays free of Flutter. `packages/readpub_reader` is a separate Flutter
package that displays `EpubRenderSession` chapters in the official
`webview_flutter` WebView and maps browser positions to readpub locators.

`ReaderController` owns the render session and `ReadingServices`, never the
publication. It loads one resource at a time, injects `readerLocationScript`
and a small bridge script after each load, positions the chapter from a
content-document CFI, a progression or its end, and reports the first visible
character as a `ReaderLocation` with a persistable locator. Page turns run in
the page; at a chapter edge the controller continues into the neighboring
reading-order item. Settings changes reload the chapter and restore the last
location. Links inside the content that load another resource are followed
and recognized; every URL outside the session is refused and reported, so the
application decides whether and how to open it.

The WebView sits behind a narrow `ReaderSurface` interface: load, reload, run,
evaluate and page-finished, navigation and message callbacks. Controller logic
is unit tested with a scripted surface, and another WebView plugin can
implement the interface. Evaluations always return JSON strings, because
WebKit returns values while Android returns them JSON-encoded.

JavaScript is enabled for host-injected scripts; publication scripts stay inert
through script replacement and the session's `script-src 'none'` policy.
Android file and content access are disabled. Integration tests run the
example app's original sample book on the iOS simulator and an Android
emulator. They exposed two defects fixed during development: prepared
reflowable chapters lacked a viewport declaration, so mobile WebViews laid
them out at desktop width, and reloading a URL with an empty fragment was a
same-document navigation on Android.

Page-turn animations, highlight rendering, synthetic spreads and fixed-layout
zoom are left for later work; the locator and selection APIs are the
foundation for highlights.
