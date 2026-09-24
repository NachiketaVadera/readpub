## 0.1.0-dev.1

* Add `ReaderController`: chapter loading, page turns across reading-order
  items, navigation to locators and table-of-contents links, settings changes
  that keep the reading location, selection and location reporting, and
  external-link interception.
* Add `ReaderView`, a `webview_flutter` view with edge taps, swipes and keys
  that turn pages, mirrored for right-to-left publications.
* Add the `ReaderSurface` abstraction with a `webview_flutter` implementation.
* Add an example app and integration tests verified on the iOS simulator
  (WebKit) and an Android emulator (Android System WebView).
