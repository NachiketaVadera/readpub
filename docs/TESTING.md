# Verification strategy

Paths and commands refer to the core package, `packages/readpub`, unless they
name the Flutter reader.

Tests under `test/` cover primitives, independent ZIP interoperability and
EPUB parsing. Python-generated EPUB fixtures exercise metadata, spine, nav/NCX,
xml:base, encodings, encryption and malformed inputs with explicit value/byte
assertions. The fixture directory documents generation and scope.

Verify byte ranges at zero, EOF and beyond EOF; empty data; defensive copies;
file errors; missing resources; close behavior; concurrent reads; stored and
Deflate data; CRC errors; truncated data; duplicate and malicious names; entry
counts and size/ratio limits; incorrect declared output sizes; URI encoding,
fragments, queries and root escape. Assert bytes, identities and exception types,
not merely absence of a throw.

Local checks:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart run example/read_archive.dart test/fixtures/independent-python.zip
dart run example/serve_epub.dart test/fixtures/epub/render-assets.epub
dart run example/reading_services.dart test/fixtures/epub/reading.epub whale
dart pub publish --dry-run
```

The publish dry run validates packaging only; it does not publish the package.
Remote pub.dev checks may need network access. Public API docs are checked by
analysis and can additionally be generated with `dart doc`.

The rendering corpus sends real loopback HTTP requests for the contents page,
XHTML/HTML chapters, CSS, images, font ranges, HEAD and invalid ranges. It checks
CSP/no-sniff headers, content transformations, legacy encodings and session
lifecycle. These tests verify serving behavior but not browser-specific page
geometry.

The EPUB corpus also checks byte/element/depth limits, fatal unsafe optional
navigation, NCX fallback, Unicode with percent escapes, immutable model equality,
resource lifecycle and JSON output.

Reading services have their own behavior tests:

- `cfi_test.dart`: every relevant example from EPUB CFI 1.1 round-trips; 28
  malformed expressions are rejected with offsets; sorting follows the
  specification's ordering rules; ranges are built and compared.
- `locator_test.dart`: JSON round trips, extension preservation, immutability
  and rejection of invalid persisted values.
- `document_text_test.dart`: block roles, whitespace, exclusions, CRLF and
  entities, legacy HTML and SVG, limits, and CFI conversion in both directions
  for every text offset of two documents, including assertion correction.
- `reading_services_test.dart`: spine package paths, positions and their JSON
  cache, titles, locator creation and restoration fallbacks, publication CFI
  conversion and correction, and search options against the `reading` fixture.
- `search_matching_test.dart`: case and diacritic folding across scripts,
  whitespace and soft hyphens, surrogate pairs and whole words.
- `render_session_test.dart`: every text offset has the same CFI in original
  and prepared XHTML and HTML documents.
- `location_script_test.dart`: the browser script's API surface and, when
  Node.js is installed, its JavaScript syntax.

The browser location script is checked against Dart-computed CFIs in a real
browser with `tool/location_script_samples.dart`, which serves a book and writes
sample CFIs and expected text; VERIFICATION.md records the results. Performance
is measured separately with `tool/benchmark.dart` (PERFORMANCE.md).

`w3c_suite_test.dart` runs 35 tests vendored from the W3C EPUB 3 test suite
(`test/fixtures/w3c`, rebuilt reproducibly by `tool/vendor_w3c_tests.py` from a
pinned checkout). Each has an observable requirement in
`tool/conformance_checks.dart` or requires an error, and the test fails if the
outcome changes. The complete suite is run with `tool/conformance.dart`, which
processes every publication, asserts the same requirements and reports expected
errors and suite defects separately (ADR 0013, COMPATIBILITY.md):

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/w3c/epub-tests.git
cd epub-tests && git sparse-checkout set tests && cd tests && sh generateEpubs.sh
dart run tool/conformance.dart /path/to/epub-tests/tests report.json
```

The Flutter reader package has its own tests: `flutter test` in
`packages/readpub_reader` runs controller unit tests against a scripted
surface, and `flutter test integration_test/reader_test.dart -d <device>` in its
example runs the reader on a simulator or emulator, asserting where located
text appears on screen after navigation, relayout and restoration. Decoration
tests compare drawn marks with the decorated text character by character:
every visible decorated character must be marked and every visible mark must
lie on decorated text, which catches both misplaced and missing marks.

Fuzzing remains future work and is not a substitute for these deterministic
tests.
