# Verification

Verified on 2026-09-24 with Dart 3.13.4 stable on macOS 27.0 arm64 (Apple M4
Pro). Commands and paths refer to the core package, `packages/readpub`, except
in the Flutter reader section.

- `dart analyze --fatal-infos`: no issues.
- `dart test`: 227 tests passed: 36 vendored W3C suite tests, 53 CFI, 17
  document text, 16 locator, 17 reading services, 5 search matching, 2 location
  script (including `node --check` with Node.js 24.15.0), 11 rendering, 35 EPUB
  parser and 35 foundation tests.
- `dart format --output=none --set-exit-if-changed .`: 61 Dart files, none
  changed.
- `dart run example/read_epub.dart test/fixtures/epub/epub3-rich.epub`: correct
  refined title/author, fixed layout, RTL, reading order, nested TOC and text read.
- `dart run example/reading_services.dart test/fixtures/epub/reading.epub whale`:
  six positions with the malformed chapter reported, four titled search results
  with publication CFI ranges, and a saved locator restored by CFI.
- `dart pub publish --dry-run`: package contents inspected; one advisory
  warning remains (no homepage/repository URL). The repository's `docs/` and
  roadmap are outside the package. No URL was invented; nothing was published.
- Independent corpus: 35 original Python-generated EPUBs, plus ZIP fixtures.

## W3C EPUB 3 test suite

The suite (`w3c/epub-tests`, commit `4cc654f`, 2026-09-16) was sparsely cloned
into a scratch directory with the user's approval, built with its
`generateEpubs.sh` into 209 publications and run with `tool/conformance.dart`.

- First run: 200 publications processed; 9 failed. Three failures were XML
  errors that the tests require or allow; six were defects or deviations,
  fixed as recorded in ADR 0013 (ZIP option flags, package version, leaking
  and path-absolute URLs, missing spine files).
- Reviewing each test's stated requirement found three more gaps in
  publications that had opened: image-only navigation labels, metadata
  direction and foreign content images. All were fixed.
- Final run: every publication opens; 30 asserted requirements hold (29
  publications checked, plus the fallback check of a suite-defect publication);
  3 expected XML errors occur; 175 publications process without errors but have
  visual or behavioral pass criteria; 2 publications report a missing
  `page_2.png` because the suite's manifests misname the file.
- 35 of these tests are vendored in `test/fixtures/w3c` and run by
  `test/w3c_suite_test.dart`. Rebuilding them with `tool/vendor_w3c_tests.py`
  produced identical bytes, including after changing checkout timestamps.
- `ocf-zip-comp` rebuilt with Bzip2 members and `ocf-zip-mult` rebuilt as a
  split archive were both rejected, as the specification requires.

This run did not exercise a reading system: rendering, layout, media, scripting
and user-interface requirements remain unverified.

## Browser location contract

`tool/location_script_samples.dart` served the `render-structure` and `reading`
fixtures, and `readerLocationScript` was evaluated in the Claude desktop app's
Chromium-based browser pane against CFIs and expected text computed by
`DocumentText`. For each sample the check resolved the CFI in the browser DOM,
compared the following text, and regenerated the CFI from the DOM point:

- `render-structure` XHTML (UTF-8 byte order mark, XHTML 1.1 doctype, named
  entities, CRLF, script, iframe, object and SVG script placeholders): every
  offset, 29 points and 29 ranges, zero mismatches; ranges crossing into SVG text
  round-tripped. `application/xhtml+xml` rendered `&nbsp;&mdash;` correctly.
- `render-structure` legacy HTML (Windows-1252, inline script placeholder, parsed
  by the browser's HTML parser): every offset, zero mismatches.
- `reading` chapter one (CRLF, entities inside `em`, 42 blocks): 17 points and
  10 ranges covering paragraph, heading and cross-paragraph boundaries, zero
  mismatches.
- Paged flow on the same chapter: `scrollToCfi` moved to page-aligned columns
  with the target visible, `firstVisibleCfi` reported each page's first
  character, and `scrollToProgression(0)` returned to the start.

The browser check also exposed an SVG `script` placeholder inheriting the SVG
namespace; placeholders now declare the XHTML namespace. WebKit, Android WebView
and real devices have not been verified.

## Flutter reader

`packages/readpub_reader` was verified with Flutter 3.47.5 on 2026-09-24:

- `flutter analyze`: no issues in the package and example.
- `flutter test`: 9 controller tests passed.
- Integration tests: all 4 passed on an iPhone 16 simulator (iOS 18.5, WebKit)
  and on an Android 17 emulator (Android System WebView 145). They page through
  chapters, cross chapter boundaries in both directions, navigate to contents
  entries and search results, apply a dark theme and larger text, reopen a
  saved locator in a new reader, select text, follow a footnote and its return
  link, refuse an external link, and scroll, asserting that located text is
  inside the viewport.
- The example app was driven on the Android emulator with taps and swipes;
  screenshots showed paged chapters, the dark theme at larger text size and the
  nested contents drawer.

Device testing exposed two defects that unit tests and desktop browsers had not:
reflowable chapters needed a viewport declaration, and reloading a URL with an
empty fragment did not reload on Android. Both were fixed. Physical devices,
tablets and macOS have not been tested.

## Performance

`tool/benchmark.dart` ran three times on a 108.8 MB synthetic book (300
chapters, 3.6 million characters, 300 images, 20 MB stored audio, 3,300 TOC
entries). Results and the resulting decisions are in PERFORMANCE.md. The
benchmark exposed two defects that were fixed and are covered by tests:
whole-member re-reads and bitwise CRC for every range request (9.8 s for twenty
64 KiB reads of the audio, now 20 ms), and point locators between blocks whose
text context disagreed with their CFI.

## History

A Terra agent implemented the initial parser. After the agent reached its usage
limit, the parent completed model integration, metadata normalization, namespace
and URI hardening, navigation recovery, encryption and independent verification.
Tests exposed and fixed lost guide fragments, title selection, namespace confusion,
missing-nav recovery and mixed Unicode/percent-encoded path decoding. The
reading-services phase exposed and fixed literal XHTML entities in prepared
chapters, UTF-8 byte order mark failures and CFI-breaking removal of active
content.

The direct Dart SDK executable avoids the installed Flutter wrapper's cache
updates. This does not make the package depend on Flutter.

This evidence is not proof of complete EPUB conformance. Official corpus testing,
fuzzing and profiling on real large books and phones remain future hardening.
See COMPATIBILITY.md.
