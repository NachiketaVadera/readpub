# Implementation status and roadmap

Last updated: 2026-09-24. Working package name: `readpub`.

This is an internal development document at the repository root, outside both
packages, so it is never published.
It records the intended product, the implementation that exists, and the work
still required. Update it when a subsystem or its verification status changes.

## What we are building

Build a production-grade, reusable, pure-Dart EPUB 2/3 engine behind a premium
Flutter reading application. A consuming app should receive a normalized
publication, navigation, resources, persistent locations and reading services
without having to understand ZIP, OPF, NCX, encryption metadata or EPUB paths.

The package takes architectural inspiration from Readium Kotlin, Swift,
TypeScript and Readium CSS. It is an independent implementation, with no Readium
affiliation or endorsement. W3C specifications are authoritative; official test
suites and multiple Readium implementations inform compatibility decisions.
Adapted code and distributed assets must retain required attribution and licenses.

The core remains idiomatic modern Dart with a small public API, immutable value
models, strict analysis, typed failures, bounded resource access and behavioral
tests. It must not depend on Flutter, `dart:ui`, platform channels, FFI or native
reader libraries. The core package is `packages/readpub`, currently targets Dart
3.13+, and runs on Dart VM and Flutter host runtimes. Its `dart:io` implementation
does not support Flutter Web.

The original brief separated platform rendering from the core. The later request
to implement rendering added a pure-Dart browser serving/preparation bridge.
Actual browser layout, WebView integration and Flutter UI remain separate layers.

## What exists today

| Area | Implemented behavior |
| --- | --- |
| Package foundations | Core Dart package in `packages/readpub` beside the Flutter reader package, selective public exports, strict analyzer configuration, BSD 3-Clause license, attribution, architecture and decision records, usage examples. |
| Assets and archives | File and memory assets with half-open byte ranges; replaceable archive interface; single-disk ZIP32 stored/Deflate support, CRC validation and entry/path/size/ratio checks. |
| Resources and fetching | Lazy archive resources, media types, full/range reads, explicit ownership and close behavior, typed failures and publication-relative URI resolution. |
| Publication model | Immutable metadata, contributors, subjects, links, reading order, resources and collection/navigation trees; structural equality and JSON output. |
| EPUB package parsing | OCF container, selected OPF rootfile, manifest, spine, linear/non-linear content, fallback relationships, bindings, nested collections and cover references. |
| Metadata | EPUB 2 metadata and EPUB 3 refinements, contributor roles, dates, subjects, identifiers, languages, accessibility, series, duration, rendition properties and reading progression; raw records retained. |
| Navigation | Nested EPUB 3 XHTML TOC, landmarks and page lists; EPUB 2 NCX fallback and legacy guide landmarks. |
| Paths and XML | Namespaces, inherited `xml:base`, Unicode and percent encoding, query/fragment preservation, bounded XML parsing, UTF-8/UTF-16 package XML and controlled recovery diagnostics. |
| Font obfuscation | IDPF and Adobe deobfuscation, including resource range reads; unknown encryption declarations preserved and unsupported reads rejected. This is not DRM. |
| Browser bridge | `EpubRenderSession` serves a contents page, prepared XHTML/HTML and manifest assets from an ephemeral loopback origin; GET/HEAD and single byte ranges for non-document resources. |
| Reader presentation | Light/dark/sepia themes, font scale, line height, margins, scroll flow and CSS-column paged flow; fixed-layout viewport sizing and spine overrides. |
| Content preparation | Bounded document preparation, legacy HTML and byte-order-mark decoding, HTML named entities in XHTML, reader CSS injection, active markup replaced by inert placeholders and restrictive response policies. Publisher text, styles, resource relationships and CFI structure are retained. |
| Locators | Immutable `Locator`, `Locations` and `LocatorText` with validated JSON round trips, Readium field names, preserved extension fields and a documented persistence policy (ADR 0007). |
| EPUB CFI | Grammar-based parser, syntax tree, canonical serializer and escaping, specification sorting, ranges and range construction; spine package paths recorded while parsing (ADR 0008). |
| Text extraction | `DocumentText` for XHTML, HTML and SVG: normalized reading text, block roles, list/quote depth, ruby handling, exclusions and bidirectional text-offset/CFI mapping with ID and text assertion correction. |
| Reading services | `ReadingServices`: bounded document cache, locators from links, progression, CFIs and text ranges, locator restoration with ordered fallbacks, deterministic cacheable positions and lazy search behind `SearchService` (ADR 0009). |
| Renderer location contract | Structure-preserving preparation verified for every text offset, a documented CFI exchange contract and `readerLocationScript`, verified in a Chromium-based browser (ADR 0010). |
| Archive performance | Table-driven CRC-32; stored members verified once in bounded chunks, then read by range (ADR 0012). |

The renderer uses original, limited reader CSS. Readium CSS was evaluated and
deferred (ADR 0011). Browser layout is not implemented in Dart; CSS columns do
not provide a measured pagination engine. Durable reading positions come from
the text-based reading services, not from rendered pages.

## Verification achieved

The last recorded implementation verification used Dart 3.13.4 stable on macOS
arm64 on 2026-09-24. These are results from that verification, not a guarantee
that every future checkout has passed them:

- 227 tests passed: 36 vendored W3C suite tests, 53 CFI, 17 document text, 16
  locator, 17 reading services, 5 search matching, 2 location script, 11
  rendering, 35 EPUB parser and 35 foundation tests.
- Strict static analysis reported no issues; formatting covered 61 Dart files.
- The W3C EPUB 3 test suite (209 publications) opens completely; 30 observable
  requirements are asserted and hold and expected XML errors occur. Six
  deviations and three processing gaps it exposed were fixed (ADR 0013). The 35
  relevant tests are vendored and run with the ordinary test suite.
- The independent corpus contains 35 original Python-generated EPUB fixtures,
  plus ZIP fixtures, with explicit metadata, navigation, byte, text, CFI and
  failure checks. CFIs round-trip for every text offset of the test documents,
  and prepared chapters keep the CFI of every text offset.
- The browser location script matched `DocumentText` CFIs and text with zero
  mismatches in a Chromium-based browser for XHTML, legacy HTML and paged flow.
- A 108.8 MB synthetic book was profiled; ranged media reads went from 9.8 s to
  20 ms for twenty requests after the archive changes.
- The examples ran successfully. The core package's publish dry run reports one
  advisory warning: missing homepage/repository metadata. No release has been
  published.

See [verification evidence](docs/VERIFICATION.md),
[performance](docs/PERFORMANCE.md) and [test strategy](docs/TESTING.md).
Synthetic tests, HTTP integration tests and one browser engine do not establish
complete EPUB conformance, browser pagination correctness or production
readiness across Flutter devices.

## Current limits

The implementation is a working parsing, resource, location and search
foundation with a browser bridge, not yet a complete Readium-equivalent reading
toolkit.

- CFI resolution does not follow indirection into iframes, objects or SVG
  images inside content documents; it stops at the referencing element.
  Temporal and spatial offsets are parsed but not mapped to media. Generated
  CFIs carry ID assertions but no text assertions.
- Text extraction does not evaluate CSS (`display: none`, generated content) and
  does not classify footnotes or asides. Search has simple lowercase and
  diacritic folding for Latin, Greek, Cyrillic, Arabic and Hebrew; no stemming,
  full case folding or CJK word segmentation.
- Positions are text-based and not interchangeable with Readium's byte-based
  positions. Locators include positions only after positions are computed.
- The location script is verified in a Chromium-based browser and, through the
  Flutter reader, in iOS simulator WebKit and Android emulator WebView; physical
  devices are unverified. Precise pagination measurement beyond CSS columns
  and annotation storage remain open.
- Fixed layout, RTL and vertical writing depend on publisher CSS and browser
  behavior; no comprehensive layout/device conformance has been demonstrated.
- Media-overlay associations and durations are parsed; SMIL timelines and playback
  are not implemented. Scripted EPUB content is blocked by the bridge.
- The first OPF rootfile is selected, as the specification requires.
  Alternate-rendition selection, container links, signatures and rights
  documents are not interpreted.
- ZIP64, multi-disk archives and ZIP encryption are rejected. Deflated entry
  ranges require full entry decompression within configured limits.
- HTTP(S) references can be retained, but remote resources are not fetched.
  Media-type recovery uses extensions, not content sniffing.
- Publication model JSON is library-specific output, not a Readium Web
  Publication manifest. Locator JSON is the persistence format (ADR 0007).
- The W3C suite was run at the processing level only; its rendering, media,
  scripting and user-interface tests need a reading system. No fuzz campaign
  has been completed, and profiling used synthetic content on a desktop
  machine only.
- CSS `url()` references that leave the container are not rewritten for the
  browser. A locator identifies a resource by href, so duplicate spine items
  share locators; publication CFIs distinguish them.

[Compatibility](docs/COMPATIBILITY.md) is the detailed record of supported
behavior, recovery rules and intentional deviations.

## Core implementation status

Items 1 to 6 of the original core roadmap are implemented with documented
designs, narrow public APIs and behavioral tests. Item 7 is partly complete.

1. **Locators and persistent locations.** Done (ADR 0007).
2. **EPUB CFI.** Done for syntax, sorting, ranges, package paths and
   content-document resolution (ADR 0008). Remaining: indirection into
   documents embedded in content documents, and media mapping of temporal and
   spatial offsets, when a consumer needs them.
3. **Text extraction.** Done (ADR 0009). Remaining: optional footnote/aside
   roles and CSS-aware visibility if consumers require them.
4. **Positions and progress.** Done (ADR 0009).
5. **Search.** Done, with an interface for application indexes (ADR 0009).
   Remaining: language-aware tokenization and full case folding.
6. **Renderer support.** Structure-preserving preparation, the location
   contract and a browser reference script are done (ADR 0010). Readium CSS was
   evaluated and deferred until device verification is possible (ADR 0011). No
   preparation extension point was added because no consumer needs one yet.
   Remaining: verify the script in WebKit and Android WebView.
7. **Parser compatibility and performance.** Large-book profiling is done and
   the measured range-read bottleneck is fixed (ADR 0012, PERFORMANCE.md). The
   W3C EPUB 3 test suite was run and every processing failure it exposed was
   fixed (ADR 0013). Remaining: real-world large illustrated books, profiling on
   phones, and the suite's rendering and behavior tests in a reading system.

## Flutter reader

`packages/readpub_reader` is a separate Flutter package (ADR 0014), verified on
the iOS simulator and an Android emulator. It provides:

- WebView lifecycle, a navigation policy confined to the render session,
  chapter switching, platform setup guidance and host script injection that
  keeps publication scripts disabled.
- Paged and scrolled reading with page controls (edge taps, swipes, keys,
  mirrored for right-to-left), continuous page turns across reading-order
  items, and progress from locations and positions.
- Location restoration after settings changes, reopening and relayout, using
  locator resolution and the location script; selection-to-locator mapping.
- Highlights and underlines drawn for locators in named groups as an overlay
  that leaves CFIs intact, with tap reporting (ADR 0015).
- An example app with contents, bookmarks, highlights, search, themes and text
  size.

A premium reader still needs:

- Annotation notes and storage, page-turn animations, synthetic spreads and
  fixed-layout zoom, and accessible reading controls.
- Device verification on physical phones and tablets for reflowable and
  fixed-layout books, RTL, vertical writing, embedded fonts, media and
  accessibility, and macOS verification.

The existing bridge requires the host to keep the session and publication alive,
restrict JavaScript to host-injected scripts and handle outbound navigation
deliberately. See [rendering behavior and responsibilities](docs/RENDERING.md)
and [reading services](docs/READING.md).

TTS and media-overlay playback may be future reader-layer capabilities, but are
not implemented. Bookshelf UI, database persistence, cloud sync, AI features and
page-turn animations belong to consuming applications. DRM/LCP is explicitly out
of scope for this core implementation; its absence is not an unfinished promise.
PDF, audiobooks, CBZ and other formats are future extension considerations only.

## Hardening and release readiness

- Track conformance by capability instead of claiming blanket support; extend
  the vendored W3C tests as new requirements become observable.
- Expand malformed-input and fuzz testing across ZIP, XML, URIs, content
  preparation, CFI parsing and search.
- Repeat the benchmark with real large illustrated books and on phones; the
  synthetic 100 MB+ baseline is recorded in PERFORMANCE.md.
- Test browser behavior and the location script on supported host platforms
  and real Flutter devices.
- Review API stability, ownership, cancellation where needed, diagnostics,
  resource limits and locator/positions persistence compatibility before a
  stable release.
- Add CI, complete documentation/examples for implemented reading services,
  confirm dependency licenses and preserve attribution.
- Finalize package name and repository metadata, review published contents and
  run package validation. Describe an early release as a prerelease foundation
  until the broader quality claims have evidence.

Publication to pub.dev is a separate release action. This roadmap does not imply
that the package has been published or authorize publication.

## Definition of success

A Flutter reader can open an asset, inspect metadata and navigation, request
prepared content and resources, search text and save/restore stable locators
without implementing EPUB internals. The core now provides each of these
capabilities; a Flutter reader built on them and verified on devices is the
remaining evidence. The core stays independent of Flutter and
UI, and claimed compatibility is backed by conformance, security, performance
and integration evidence.
