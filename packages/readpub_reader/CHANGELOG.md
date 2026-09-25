## 0.1.0-dev.1

* Ignore superseded chapter completions, script injections and restoration
  results so delayed browser work cannot replace the current reading location.
* Clear selections on chapter changes and reloads, and discard pending selection
  results after navigation or explicit clearing.
* Prepare hosted core dependency and repository metadata for publication; keep
  local development overrides outside published archives.

* Add `ReaderController`: chapter loading, page turns across reading-order
  items, navigation to locators and table-of-contents links, settings changes
  that keep the reading location, selection and location reporting, and
  external-link interception.
* Add `ReaderView`, a `webview_flutter` view with edge taps, swipes and keys
  that turn pages, mirrored for right-to-left publications.
* Add the `ReaderSurface` abstraction with a `webview_flutter` implementation.
* Add decorations: `ReaderController.applyDecorations` draws highlights and
  underlines for locators in named groups, redrawn across page turns,
  relayout and chapter changes, and `onDecorationActivated` reports taps on
  them. `clearSelection` clears the page selection.
* Add an example app with highlights, and integration tests verified on the
  iOS simulator (WebKit) and an Android emulator (Android System WebView).
