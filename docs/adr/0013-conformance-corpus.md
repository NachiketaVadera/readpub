# ADR 0013: Changes from the W3C EPUB conformance corpus

Status: accepted and implemented.

The W3C EPUB 3 test suite (`w3c/epub-tests`, commit `4cc654f`, 2026-09-16, W3C
Software and Document License) was built into 209 EPUBs with the suite's
`generateEpubs.sh` and run through parsing, resource access, text extraction,
render preparation and positions with `tool/conformance.dart`. Nine publications failed initially. Their requirements, not our
earlier choices, decided each change:

- **Stored ZIP members with compression-option flags** (`cnt-css-fonts_woff2`).
  Info-ZIP `zip -9` sets general-purpose bits 1 and 2 on members it chooses to
  store, typically already-compressed fonts and images. They are defined only
  for compressing methods, so they are now ignored; encryption flags and other
  compression methods are still rejected.
- **Package versions below 3.0** (`pkg-version-backward`). Reading systems must
  attempt to process them, so any version is processed with a
  `package-version-unsupported` warning.
- **Leaking and path-absolute URLs** (`ocf-url_link-leaking-relative`,
  `ocf-url_link-path-absolute`). The container root URL resolves `/` and `..`
  to the root, so these references are clamped to the container instead of
  rejecting the publication (ADR 0004 amendment), and prepared content rewrites
  them so browsers load them from the session.
- **Missing spine resources** (`lay-pp-spine-overrides_image-spine-reflow`,
  whose manifest points at a nonexistent file). A missing spine file is now a
  `resource-missing` diagnostic; when a manifest fallback exists it is used.
- **Manifest fallbacks** (`pub-foreign_*`). `EpubPublication.fallbackFor`
  follows fallback chains. The render session displays and serves the first
  supported fallback, and reading services compute text, CFIs and positions
  from the document a reader displays.

Reviewing every test's stated requirement found three processing gaps among
tests that had opened without errors: image-only navigation labels were
dropped (`nav-non-text_img*`), metadata base direction was not exposed
(`pkg-dir*`), and foreign images referenced from content were served
unchanged (`pub-foreign_image`). Navigation labels now use `img` alternative
text and `title`, `LocalizedString` and `Contributor` expose `direction`, and
foreign resources with fallbacks are served as their core-media-type fallback.
The ZIP container tests were rebuilt with Bzip2 compression and as a split
archive, because the suite's script cannot produce them; both are rejected as
the specification requires.

The runner now asserts 30 requirements this library can observe. Most other
tests judge rendering, scripting, media or user interface behavior and must be
run in a reading system built on this package.

The 35 tests with an asserted requirement or a required error are vendored in
`test/fixtures/w3c` and run by `test/w3c_suite_test.dart`, so regressions fail
the ordinary test suite. `tool/vendor_w3c_tests.py` rebuilds them byte for byte
from the pinned commit; test files are packaged unmodified except for the two
container tests, which the suite describes but cannot build. The license notice
travels with the fixtures, which are excluded from the published package
because they are 2.6 MB and only the repository's tests use them.
