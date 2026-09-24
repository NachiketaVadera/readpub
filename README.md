# readpub

An independent EPUB reading toolkit for Dart and Flutter, inspired by Readium.
It is not affiliated with or endorsed by the Readium Foundation.

| Package | Description |
| --- | --- |
| [`readpub`](packages/readpub) | Pure-Dart EPUB 2/3 engine: parsing, publication model, locators, EPUB CFI, reading text, positions, search and a loopback render session for browsers and WebViews. No Flutter dependency. |
| [`readpub_reader`](packages/readpub_reader) | Flutter reader built on `readpub`: `ReaderController` and `ReaderView` for paged and scrolled reading in a WebView on iOS, Android and macOS, with an example app. |

## Repository layout

```text
packages/
  readpub/          Core Dart package (lib, test, tool, example)
  readpub_reader/   Flutter package and its example app
docs/               Architecture, design decisions (ADRs), compatibility,
                    testing, verification and performance notes
IMPLEMENTATION.md   Implementation status and roadmap
```

Each package resolves its dependencies on its own; `readpub_reader` depends on
`readpub` through a path dependency.

## Development

```sh
cd packages/readpub
dart pub get
dart analyze --fatal-infos
dart test
dart format --output=none --set-exit-if-changed .
```

```sh
cd packages/readpub_reader
flutter pub get
flutter analyze
flutter test
cd example
flutter test integration_test/reader_test.dart -d <simulator-or-emulator>
```

See [architecture](docs/ARCHITECTURE.md), [decisions](docs/adr),
[testing](docs/TESTING.md) and [verification](docs/VERIFICATION.md).

## License

BSD 3-Clause. See [LICENSE](LICENSE) and
[ATTRIBUTION](packages/readpub/ATTRIBUTION.md).
