## 0.1.0-dev.1

* Correct total progression through shortened final positions so the end of a
  book reaches 100%, while existing position boundaries remain unchanged.
* Reject inconsistent cached position lengths, counts and unreadable flags.
* Preserve CFI range endpoints when package indirection occurs in local range
  paths; reject ranges spanning different spine documents.

* Add the initial asset, ZIP archive, fetcher, resource, and URI foundations.
* Add EPUB 2/3 package, metadata, manifest/spine and nested navigation parsing.
* Add immutable publication models, metadata refinements, rendition properties,
  collections, bindings and fallback/media-overlay relationships.
* Add bounded XML processing and namespace-aware, xml:base-aware URI handling.
* Add IDPF and Adobe font deobfuscation with unsupported-encryption protection.
* Add parser diagnostics, resource text decoding and EPUB reading example.
* Add loopback browser rendering for XHTML/HTML chapters, styles, images,
  media and deobfuscated fonts, with HTTP range responses.
* Add reader themes, scroll and paged CSS modes, a contents page, content limits
  and a no-script browser policy.
* Add immutable `Locator`, `Locations` and `LocatorText` values with validated
  JSON persistence and extension fields.
* Add an EPUB CFI 1.1 parser, canonical serializer, specification sorting,
  ranges and spine package paths (`EpubPublication.spine`).
* Add `DocumentText`: normalized XHTML, HTML and SVG reading text with block
  roles and bidirectional CFI mapping, including ID and text assertion
  correction.
* Add `ReadingServices`: locators from links, progression, CFIs and text
  ranges; locator restoration; deterministic, cacheable positions; lazy search
  behind the `SearchService` interface.
* Add `readerLocationScript`, a browser reference implementation of the
  renderer location contract.
* Preserve CFI structure in prepared chapters: active elements become inert
  placeholders and reader styles are appended instead of inserted.
* Fix XHTML named character references such as `&nbsp;` being served as
  literal text, and UTF-8 content documents with a byte order mark failing to
  parse.
* Content preparation failures are now reported as `ContentException`.
* Verify stored ZIP members once and read later ranges directly, and compute
  CRC-32 with lookup tables; range requests for large media no longer re-read
  and re-check the whole member.
* After running the W3C EPUB 3 test suite:
  * Accept stored ZIP members with Info-ZIP compression-option flags; `zip -9`
    EPUBs with already-compressed fonts or images previously failed to open.
  * Resolve leaking and path-absolute URLs at the container root, with
    diagnostics, instead of rejecting the publication; rewrite them in
    prepared content.
  * Process packages of any version, with a diagnostic.
  * Diagnose missing spine files instead of failing, and follow manifest
    fallbacks (`EpubPublication.fallbackFor`) in reading services and the
    render session, including foreign content images.
  * Use image `alt` text and `title` for image-only navigation labels.
  * Expose metadata base direction on `LocalizedString` and `Contributor`.
* Declare a device-width viewport in prepared reflowable chapters, which mobile
  WebViews otherwise lay out at desktop width, and handle right-to-left paged
  progression in `readerLocationScript`.
* Clamp `readerLocationScript` scrolling in scrolled chapters. WebKit let the
  script scroll past the end until the native scroll view corrected it, so a
  location near the end of a chapter was briefly reported where it was never
  displayed.
* Add `tool/conformance.dart` for running EPUB test corpora, and vendor 35 W3C
  EPUB 3 tests as repository fixtures (excluded from the published package).
