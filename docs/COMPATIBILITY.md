# Compatibility

The package parses EPUB publication structure and exposes resource bytes; it is
not a complete reading system or an EPUB validator. Tested with original EPUB 2
and EPUB 3 fixtures and the W3C EPUB 3 test suite (see below). No complete
standards-compliance claim is made.

| Capability | Status |
|---|---|
| EPUB 2 OPF, NCX, guide, legacy metadata | Supported |
| EPUB 3.0 / 3.2 / 3.3 common package and navigation structures | Supported within the boundaries below |
| Manifest, spine, metadata refinements, cover, collections, bindings | Supported |
| Manifest fallbacks | Followed for spine items and content resources a browser cannot display, and for missing spine files |
| Metadata base direction (`dir`) | Exposed on titles and contributors, inherited from the package |
| Fixed layout / RTL | Served with viewport sizing and publisher CSS; host browser lays out content |
| Vertical writing | Content CSS preserved as bytes; no CSS interpretation |
| Nested TOC / landmarks / page lists | Supported; image-only labels use `alt` or `title` |
| Media overlays | Associations and declared durations; no SMIL timeline parsing/playback |
| IDPF / Adobe font obfuscation | Supported, including byte ranges |
| Other encryption | Declarations preserved; reads fail explicitly |
| Scripted content | Resource/property preserved; never executed |
| EPUB CFI 1.1 syntax | Parsing, canonical serialization, escaping, sorting and ranges; strict grammar |
| EPUB CFI resolution | Content documents: element/chunk steps, virtual positions, ID and text assertion correction; package paths through the spine; indirection inside content documents stops at the referencing element; temporal/spatial offsets parsed but not mapped to media |
| Locators | Readium field names, validated JSON round trip, extension fields; no Readium schema conformance claim |
| Text extraction | XHTML, HTML and SVG reading text with block roles and CFI mapping; CSS visibility and generated content not evaluated |
| Positions and progression | Deterministic, text-based; not interchangeable with Readium's byte-based positions |
| Search | Lazy scan with case, diacritic and whole-word options; no stemming, tokenization or CJK word segmentation |
| Browser rendering bridge | Loopback serving, CSS themes, scroll/paged styles, resource ranges, CFI-preserving preparation |
| Browser location script | Verified in a Chromium-based browser, iOS simulator WebKit and Android emulator WebView; physical devices unverified |
| Flutter reader (`packages/readpub_reader`) | WebView reader with paging, navigation, settings, selection and locators; no page animations, highlight rendering or spreads |
| DRM / LCP | Not implemented |
| ZIP64 / multi-disk / ZIP encryption | Rejected |
| Remote resources | HTTP(S) links retained; no network fetch |

## Intentional boundaries and recovery

- Selects the first OPF rootfile in container.xml. Alternate renditions, container
  links, signatures and rights documents are not interpreted.
- Requires the exact mimetype content but does not enforce its ZIP entry order or
  stored method. Package parsing is not a full OCF validation pass.
- Requires namespaced OPF/DC/XHTML/NCX elements. Foreign namespace lookalikes do
  not acquire EPUB meaning. XML must be well formed; malformed optional navigation
  can fall back to NCX with diagnostics. Unsafe references and exceeded limits
  cannot be downgraded to optional-navigation warnings.
- Missing optional metadata and resources, including spine resources, are
  diagnosed; a missing or unsupported spine resource is replaced by its manifest
  fallback when one exists. Packages of any version are processed, with a
  diagnostic for versions other than 2.x and 3.x. Empty linear reading order,
  spine references to absent manifest items, duplicate IDs/hrefs, missing
  fallback associations and fallback cycles are fatal. No guessed cover or
  invented TOC is synthesized.
- XHTML remains lazy until a browser requests the chapter. Package XML supports UTF-8
  and UTF-16, forbids internal DTD subsets and never fetches external DTDs.
  `Resource.readAsString` defaults to strict UTF-8 rather than charset sniffing.
- Inherited xml:base is supported. Local references resolve against the EPUB
  container root URL: excess `..` segments and path-absolute references resolve
  inside the container, with diagnostics, as EPUB Reading Systems 3.3 requires.
  Encoded path separators and scheme-relative references are rejected. Only
  HTTP(S) external resource/navigation schemes are retained.
- ZIP members may carry the compression-option flag bits that Info-ZIP writes on
  stored members; encryption flags, compression methods other than stored and
  Deflate, and split archives are rejected.
- Common valid media types are preserved; extension fallback repairs absent,
  invalid, generic and selected historical declarations. No content sniffing.
- Date-only metadata uses the first day for partial dates. Invalid dates/durations
  are retained in raw metadata with diagnostics instead of crashing the parser.
- Publication model JSON is a library representation, not a standards-compliant
  Readium manifest. Locator JSON is the persistent format; see ADR 0007.
- XHTML content documents may use HTML named character references, which are
  decoded as browsers do for XHTML document types. XML end-of-line handling is
  applied before text offsets are counted.

Validation currently uses synthetic fixtures and independent ZIP encoders.
Official EPUB conformance corpora, fuzzing and large-book benchmarks remain future
hardening work; passing these tests does not demonstrate every EPUB feature.

## W3C EPUB 3 test suite

The suite at commit `4cc654f` (2026-09-16) was built into 209 publications and
run with `packages/readpub/tool/conformance.dart` (ADR 0013). Every publication opens. 30
requirements observable by this library are asserted and hold, including
first-rootfile selection, ignored META-INF extras, duplicate spine items,
metadata order, whitespace and direction, image navigation labels, fallbacks,
container-root URLs, font obfuscation, blocked `file:` iframes and unlisted
resources. Three tests that require or allow XML errors produce errors. Two
tests reference a file their own manifests misname; they open with diagnostics.
The ZIP compression and split-archive tests, rebuilt as the suite intends, are
rejected. The remaining 175 publications process without errors, but their pass
criteria concern rendering, layout, media, scripting or user interface and must
be judged in a reading system built on this package. The 35 tests with asserted
requirements or required errors are vendored and run by `dart test`.

## Rendering boundaries

The renderer provides a contents page and browser-readable chapter URLs. It
injects reader CSS into XHTML and legacy HTML while preserving publisher text,
relative resources, author styles and the element structure that CFIs count;
active elements become inert placeholders rather than being removed. Paged mode
uses CSS columns and depends on the host browser's layout behavior.
Fixed-layout content receives viewport sizing; precise scale/position and
gesture handling are not implemented here. Reading locations come from the
reading services and the optional location script. Remote resources and
publication scripts are blocked by the served response policy. Applications
must keep the render session alive, restrict JavaScript in WebViews to
host-injected scripts and handle outbound links intentionally. The adapter binds
only to loopback; it does not expose a network service to other devices.
