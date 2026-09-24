# Architecture

Status: EPUB parsing, rendering bridge and reading services implemented.

## Packages

The repository holds two packages under `packages/`. `readpub` is the pure-Dart
engine described here; paths in this document are relative to it.
`readpub_reader` is the Flutter reader (ADR 0014). It depends on `readpub`;
`readpub` never depends on it or on Flutter.

## Dependency direction

```text
Browser/WebView ─CFIs─→ Reading services ──→ Document text ──→ EPUB CFI
      ↓                        ↓                                  ↑
Render session ──→ Publication / navigation                       │
                               ↓                                  │
                          EPUB parser ────────────────────────────┘
                               ↓
                            Fetcher
                               ↓
                           Resource
                               ↓
                            Archive
                               ↓
                             Asset
```

Arrows denote access/dependency direction, not inheritance. The browser layer is
outside the package; it exchanges content-document CFIs with the reading
services through the host application. Locator, CFI and content decoding are
value and utility layers shared by the render session and reading services.
Format-independent errors and URI utilities sit below these layers. No lower
layer imports EPUB, Flutter, UI, FFI, or application code. The package exports a deliberately
small API through `lib/readpub.dart`.

## Decisions before implementation

An Asset is an asynchronous byte source with optional length and display name.
MemoryAsset owns a defensive copy. FileAsset opens files per operation so callers
have no persistent handle to manage. Reads use zero-based half-open ranges, with
out-of-bounds ranges rejected rather than silently truncated. Empty ranges work.
Inputs must remain unchanged while being used; concurrent external file mutation
is not snapshot-isolated.

Archive is a replaceable container interface. ArchiveEntry describes a canonical
case-sensitive name, uncompressed size, and directory status. ZipArchive implements a narrow ZIP32 framing adapter over Asset ranges and uses
the Dart SDK raw DEFLATE decoder; DEFLATE is not reimplemented. The current
archive package brings FFI transitively, so it is not used. File input uses
random access, avoiding a whole-book byte allocation. Generic Asset inputs use
the same range contract. Compressed entry ranges can require full
entry decompression. Bounded materialization and lazy access are separate promises.

Resource adds publication-relative identity and an optional media type to byte
access. Fetcher resolves resources and owns its backing archive. Closing is
idempotent; access after closing fails. An absent resource can be probed with
nullable lookup, while required access fails with a typed exception. Resources
must not outlive their owning fetcher. There is no Link dependency in this layer.

URI references and ZIP entry names are different representations. Raw ZIP names
are not percent-decoded. URI segments are decoded once, query/fragment do not
select different archive bytes, and root escape or external references are
rejected. See ADR 0004 for the deliberately restricted local URI profile.

## Publication and future reading services

Publication exposes immutable normalized Metadata, Link trees, reading order,
resources and named collections, delegating byte access to a Fetcher. Parsing
preserves format-specific metadata without exposing OPF DOMs as public API.
EPUB parser responsibilities include container.xml, OPF, nav/NCX, encryption and
normalization; they are not archive responsibilities.

Locator is a stable JSON value model independent of CFI (ADR 0007). EPUB CFI
has its own grammar, syntax tree, serializer, comparator and range model
(ADR 0008); it knows nothing about documents. `DocumentText` resolves and
generates content-document CFIs, and `EpubPublication.spine` supplies package
coordinates for publication CFIs.

Font deobfuscation decorates resource access, preserving range behavior. The
render session consumes Publication.resource and serves chapters plus assets over
an ephemeral loopback origin. It injects reader CSS into content documents while
the browser performs layout. Future transforms can decorate Resource without
changing the archive or parser layers.
Text extraction, positions, locator restoration and search are reading
services above Publication (ADR 0009). They parse content documents through the
same decoding rules as the renderer, never measure rendered pixels, and keep
only a bounded cache of parsed documents. `SearchService` is an interface so an
application can substitute a persistent index. Recoverable parser issues are
exposed as immutable warnings without a logging dependency. No global state,
implicit remote network access or database is introduced.

## Security and performance

Validate all archive entries before exposing resources. Reject ambiguous names,
traversal, unsupported encryption/compression, and unsafe links. Configure entry
counts, input size, per-entry output, aggregate declared output, and compression
ratio limits. Actual decompressed bytes must be bounded independently of headers.
CRC checking verifies integrity when data is read; opening is not a full audit.
No extraction to disk is required. XML is preflighted with bounded pull events
before DOM construction. Internal DTD subsets are rejected; external DTDs are
not fetched. This is not a complete EPUB conformance claim.

The SDK chunked decompressor performs CPU work synchronously. Those calls may
block an isolate; callers can move whole workloads to another isolate. Stored
members are verified once in bounded chunks and then read by range (ADR 0012).
Measurements are in PERFORMANCE.md. Public async streaming and a concrete remote
Asset remain future work.

## Implementation and verification plan

1. Inspect stable reference implementations and authoritative specifications.
2. Record these design decisions and ADRs before implementation.
3. Create root package, strict analysis, licensing and public documentation.
4. Implement assets, archive, resources, fetcher and URI utility with tests.
5. Review malformed input, bounds, ownership, copying and error behavior.
6. Run formatting, strict analysis, tests, example and package dry-run checks.

Each subsequent phase in the supplied brief must remain independently compiling
and tested. See COMPATIBILITY.md and REFERENCES.md for scope and evidence.

## EPUB parser design (before implementation)

EpubPublication.open accepts an Asset and parser options and returns a normalized
publication exposing metadata, readingOrder, resources, navigation, resource
access and close directly. Do not force callers through an EPUB XML/manifest
wrapper. The publication owns the fetcher; opening failures close owned state.
Immutable Link, Metadata, Contributor, Subject and collection values preserve
source-specific properties without exposing mutable XML DOM nodes.

Opening follows mimetype → META-INF/container.xml → selected OPF package →
manifest/spine/metadata → navigation/NCX/guide → encryption mappings. Package and
navigation XML are bounded and parsed eagerly; reading-order content stays lazy.
A spine entry marked non-linear remains available as a resource. Missing required
package structure is fatal; recoverable optional metadata/navigation defects
produce diagnostics. No reference causes an implicit network request.

Namespace-aware helpers separate OPF/DC/XHTML/NCX from foreign lookalikes.
Inherited xml:base resolves before each reference, while local containment is
checked before URI normalization erases traversal. Hrefs preserve encoded paths,
query and fragment. Container full-path is rooted at the archive root. Resource
media types prefer valid manifest declarations with extension fallback; the
manifest's original declaration remains available for diagnostics.

Use package:xml for parsing and package:crypto for SHA-1 font keys. Reject DTD
entity declarations and external entity expansion; allow common harmless XHTML
and NCX doctypes without fetching external identifiers. Enforce XML bytes/depth/
element count and navigation depth limits before building unbounded structures.
IDPF font obfuscation removes XML whitespace from the designated package
identifier before SHA-1 and XORs only the first 1040 bytes. Adobe obfuscation
uses the UUID identifier bytes for the first 1024 bytes. Unknown encryption is
preserved in metadata and must fail resource reads explicitly.

Metadata parsing preserves repeated values, languages, identifiers, title types,
roles, file-as refinements, prefixes, accessibility, rendition, duration,
collections, bindings and per-resource media overlays/fallback associations.
Fallback chains must detect cycles. Navigation is a tree, including structural
labels without a direct target. EPUB3 nav takes priority; NCX is fallback.

CFI, text extraction, search and positions are independent subsystems above
the parser; DRM is out of scope. The browser render session sits above
Publication and does not change parsing.

## Browser rendering bridge

`EpubRenderSession` binds to IPv4 loopback on an ephemeral port and creates a
random, unguessable path prefix. The contents page provides chapter and TOC
links. Chapter requests read bounded XHTML or HTML, insert reader styles and
serve UTF-8. CSS, images, SVG, audio, video and fonts remain lazy Resource reads;
HTTP byte ranges pass through resource ranges and font deobfuscation. The session
never owns the publication and stops independently.

The origin has a Content Security Policy disabling scripts, connections, frames
and remote resources. EPUB content remains untrusted; WebView hosts must also
restrict JavaScript and handle outbound navigation. Preparation preserves the
structure CFIs count, and `readerLocationScript` implements the browser side of
the location contract (ADR 0010). CSS themes and flow settings
are session preferences applied on page reload. Browser layout and measurements
belong to the host. See ADR 0006 and RENDERING.md.
