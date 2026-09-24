# Independent EPUB parser corpus

All books contain original synthetic content and are BSD 3-Clause licensed with
this repository. Generate them deterministically with
`python3 tool/generate_epub_fixtures.py`. Python's standard ZIP writer is
independent of the Dart implementation; mimetype is first and stored.

| Fixture | Behavior |
|---|---|
| epub3-basic | Container, OPF, manifest, spine, encoded chapter path, nav |
| epub3-rich | Title types, contributor refinements, subject authority/term, multiple languages, accessibility, rendition, RTL, non-linear spine, nested TOC, page list, landmarks, bindings, collections, fallback and overlay associations |
| epub2-ncx | EPUB2 creator attributes, cover meta, guide, nested NCX and page targets, harmless PUBLIC doctype |
| xml-base | Inherited package and manifest xml:base directory resolution |
| broken-spine | Fatal missing manifest idref |
| duplicate-manifest | Fatal ambiguous manifest identifier |
| unsafe-path | Leaking relative spine reference, resolved at the container root with diagnostics |
| fallback-cycle | Fatal cyclic manifest fallback graph |
| missing-nav | Diagnostic recovery for an absent navigation document |
| remote-resource | Preserve HTTPS reference but never fetch it implicitly |
| entity-attack | Reject an external entity declaration before expansion |
| foreign-namespace | A foreign manifest lookalike cannot supply OPF structure |
| font-idpf | SHA-1 key, XOR first 1040 bytes, leave remaining bytes unchanged |
| font-adobe | UUID byte key, XOR first 1024 bytes |
| font-unsupported | Unsupported encryption must fail resource access |
| unsafe-nav | Leaking nav link resolved at the container root with a diagnostic |
| nav-ncx-fallback | Malformed XHTML nav recovers to usable NCX |
| utf16 | UTF-16 package document with Unicode metadata |
| encoded-root | Container full-path retains literal percent and spaces |
| literal-percent | Mixed Unicode and percent-encoded resource filename |
| missing-metadata | Missing title/language produce diagnostics |
| invalid-date | Invalid date/duration are diagnosed and preserved raw |
| render-assets | Relative CSS/image references, active-content stripping, browser serving |
| render-html | Legacy malformed HTML and Windows-1252 text |
| render-utf16 | UTF-16 XHTML content document converted to UTF-8 |
| render-override | Per-spine reflowable rendition overrides fixed publication layout |
| render-structure | UTF-8 BOM XHTML with an XHTML 1.1 doctype and named entities, head/body/SVG scripts, iframe and object; head-less XHTML; Windows-1252 legacy HTML with an inline script. Prepared documents must keep every CFI |
| path-absolute | Path-absolute manifest and nav references resolved at the container root |
| version-zero | Package version "0" processed with a diagnostic |
| scheme-relative | Fatal scheme-relative manifest reference |
| encoded-traversal | Percent-encoded dot segments clamped like literal ones |
| fallbacks | JSON spine item and missing spine image with XHTML fallbacks, PSD content image with PNG fallback |
| nav-direction | Image-only navigation labels using alt and title; inherited and declared `dir` on titles and creators |
| render-urls | Content image and link URLs that leak or start with `/`, rewritten by the renderer |
| reading | Reading services corpus: CRLF XHTML with entities and inline markup, nested TOC fragments, an itemref ID, non-linear notes, a fixed-layout plate, a malformed chapter and case/diacritic search terms |

Font files are synthetic 1300-byte sequences (byte i = i mod 251), not real
licensed font programs. Their purpose is byte-transform verification only.
Some fixtures intentionally omit optional/recoverable metadata and navigation;
they are parser cases, not claims that every file is fully conforming EPUB.
