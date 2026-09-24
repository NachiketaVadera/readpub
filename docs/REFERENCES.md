# Reference inspection

Inspected on 2026-09-24. GitHub `/releases/latest` was queried for each repository;
all selected releases were marked non-prerelease. TypeScript is a monorepo: its
latest release tag is a navigator release, used here as a pinned source snapshot
for the shared package, not a claim about the shared package version.

| Project | Stable snapshot | Published |
|---|---|---|
| kotlin-toolkit | [3.4.0](https://github.com/readium/kotlin-toolkit/releases/tag/3.4.0) | 2026-09-11 |
| swift-toolkit | [3.11.0](https://github.com/readium/swift-toolkit/releases/tag/3.11.0) | 2026-07-17 |
| ts-toolkit | [navigator/2.10.3](https://github.com/readium/ts-toolkit/releases/tag/navigator/2.10.3) | 2026-09-23 |

## Sources inspected

The tagged source trees and the following implementation files informed the
architecture; no platform-specific code was translated.

- [Kotlin Asset](https://github.com/readium/kotlin-toolkit/blob/3.4.0/readium/shared/src/main/java/org/readium/r2/shared/util/asset/Asset.kt),
  [Resource](https://github.com/readium/kotlin-toolkit/blob/3.4.0/readium/shared/src/main/java/org/readium/r2/shared/util/resource/Resource.kt),
  [Publication](https://github.com/readium/kotlin-toolkit/blob/3.4.0/readium/shared/src/main/java/org/readium/r2/shared/publication/Publication.kt).
  Shared publication values and resource utilities are separate from navigator.
  Asset distinguishes resource/container, and Publication delegates to Container.
- [Swift Asset](https://github.com/readium/swift-toolkit/blob/3.11.0/Sources/Shared/Toolkit/Data/Asset/Asset.swift),
  [Resource](https://github.com/readium/swift-toolkit/blob/3.11.0/Sources/Shared/Toolkit/Data/Resource/Resource.swift),
  [Container](https://github.com/readium/swift-toolkit/blob/3.11.0/Sources/Shared/Toolkit/Data/Container/Container.swift),
  [Publication](https://github.com/readium/swift-toolkit/blob/3.11.0/Sources/Shared/Publication/Publication.swift).
  Shared Toolkit/Data separates byte access from normalized publication values.
  Resource distinguishes source URL from logical identity; transformed bytes need
  not have a physical source URL.
- [TypeScript Fetcher](https://github.com/readium/ts-toolkit/blob/navigator/2.10.3/shared/src/fetcher/Fetcher.ts),
  [Resource](https://github.com/readium/ts-toolkit/blob/navigator/2.10.3/shared/src/fetcher/Resource.ts),
  [Publication](https://github.com/readium/ts-toolkit/blob/navigator/2.10.3/shared/src/publication/Publication.ts).
  Shared fetcher and publication modules are separate from navigator. The web
  implementation uses Promise-based reads and inclusive range endpoints.
- [Readium composite fetcher proposal](https://github.com/readium/architecture/blob/master/proposals/002-composite-fetcher-api.md).
  Resource access can be composed/decorated; this is design background rather
  than a requirement to introduce all decorators in the initial package.

Across the three implementations, publication metadata is independent of byte
storage and access is delegated. Our design keeps that shared behavior, uses
Dart Futures and typed exceptions, and chooses Dart-style exclusive range ends.
The simpler byte-source Asset is deliberate; format detection is deferred.

## Standards baseline

- [EPUB 3.3, W3C Recommendation 13 January 2026](https://www.w3.org/TR/2026/REC-epub-33-20260113/):
  OCF file names and URL-to-path derivation (§4.2), ZIP requirements (§4.3), and
  package/navigation responsibilities. Storage lookup must distinguish encoded
  URLs from raw names. ZIP support alone is not EPUB conformance.
- [EPUB Reading Systems 3.3](https://www.w3.org/TR/epub-rs-33/): later reading-system
  behavior must be assessed separately from container access.
- [EPUB CFI 1.1](https://w3c.github.io/epub-specs/epub33/epubcfi/): reference for the
  deferred CFI phase, not an implemented feature or conformance claim.
- [Official EPUB tests](https://w3c.github.io/epub-tests/): future conformance
  corpus source; no third-party EPUB fixtures have been copied in this phase.

Normative specifications outrank individual toolkit behavior. The local URI
profile intentionally rejects some references a browser URL parser could accept;
see ADR 0004. EPUB parsing must eventually implement the applicable spec behavior
above this storage boundary.

## Toolchain

Dart official stable metadata returned 3.13.4, published 2026-09-15; the installed
SDK matches. Source: [Dart SDK archive](https://dart.dev/get-dart/archive).

## EPUB parsing references (2026-09-24)

Inspected the stable-tag Kotlin EpubParser, NcxParser,
NavigationDocumentParser and EpubEncryptionParser, plus Swift EPUBParser,
OPFParser, NCXParser, NavigationDocumentParser and EPUBEncryptionParser.
The files are under Kotlin readium/streamer/.../parser/epub and Swift
Sources/Streamer/Parser/EPUB in the release snapshots above.

Both implementations retain nested navigation, delegate resource access,
normalize legacy guide information and attach encryption information to
resource links. Swift exposes linear spine items separately from auxiliary
resources. This implementation follows these shared concepts, without copying
Swift's bitmap-first fallback preference: fallback associations are retained
without silently replacing a declared reading-order resource.

The TypeScript stable tree has no equivalent local EPUB ZIP/OPF parser; its
shared package consumes normalized manifest models. This absence was checked
rather than inventing a third parser comparison.

Additional normative baseline:
[EPUB 2 OPF 2.0.1](https://idpf.org/epub/20/spec/OPF_2.0.1_draft.htm),
[EPUB3 package documents](https://www.w3.org/TR/epub-33/#sec-package-doc),
[navigation](https://www.w3.org/TR/epub-33/#sec-nav), and
[font obfuscation](https://www.w3.org/TR/epub-33/#sec-font-obfuscation).

## Browser rendering references (2026-09-24)

[EPUB 3.3 content documents](https://www.w3.org/TR/epub-33/#sec-content-docs)
defines XHTML/SVG publication content, CSS resources and scripted-content
requirements. [EPUB Reading Systems 3.3](https://www.w3.org/TR/epub-rs-33/)
describes browser-facing reading-system behavior. We use a browser engine for
layout, serve a unique loopback origin and disable scripted content by default.

[Readium CSS](https://github.com/readium/css) was inspected as a reference for
scroll/paged modes, themes and accessibility considerations. The implementation
uses original small CSS rules rather than vendoring Readium CSS. Exact Readium
pagination or typography compatibility is not claimed.

The [Dart html package](https://pub.dev/packages/html) supplies maintained HTML5
parsing for legacy `text/html`; `package:xml` continues to parse XHTML.

## Reading services references (2026-09-24)

[EPUB CFI 1.1](https://w3c.github.io/epub-specs/epub33/epubcfi/) was read for
the grammar, step indexing (even element indices, odd character-data chunks,
virtual 0 and n+2 positions), UTF-16 character offsets, indirection targets,
text location assertions, side bias, sorting rules, ranges, ID correction and
circumflex escaping. Its examples are the basis of `cfi_test.dart`; the sample
document in `document_text_test.dart` is original but mirrors the example's
structure.

The Locator model follows the field names used by the Readium toolkits listed
above: `href`, `type`, `title`, `locations` (`fragments`, `progression`,
`position`, `totalProgression` and extensions such as `partialCfi`) and `text`
(`before`, `highlight`, `after`). No Readium source was translated.

[Readium CSS](https://github.com/readium/css) v2.0.5 (2026-05-13) and the
v2.0.0 release notes (2026-02-25) were inspected through the GitHub API for the
evaluation in ADR 0011: BSD 3-Clause license, `css/dist` contents and sizes,
and the injection and pagination documentation.

The [W3C EPUB 3 test suite](https://github.com/w3c/epub-tests) at commit
`4cc654f` (2026-09-16) was run for ADR 0013; its README, license (W3C Software
and Document License) and each test's `dc:description` requirement were read.
[EPUB Reading Systems 3.3](https://www.w3.org/TR/epub-rs-33/) was read for the
container root URL properties, backward version processing and foreign
resource fallbacks.

Diacritic folding for search is generated by
`packages/readpub/tool/generate_search_folding.py` from Python's Unicode 16.0.0
character database.
