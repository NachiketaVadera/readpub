# ADR 0009: Text-derived reading services

Status: accepted and implemented.

Locators, positions and search need the same view of a content document. Build
one pure-Dart text model, `DocumentText`, and derive every reading service from
it rather than from rendered pixels.

Text extraction approximates what a browser displays without author CSS:
whitespace collapses inside blocks, `br` is a line feed, `pre` keeps its
whitespace and blocks are separated by one line feed. The head, scripts,
styles, templates, ruby annotations, embedded-content fallbacks, SVG
descriptive elements and `hidden` subtrees are excluded; CSS visibility is not
evaluated. Blocks record their role, heading level, list and quotation depth
and language. Every source character keeps a mapping to its element path and
character-data chunk, so text offsets and CFIs convert in both directions.
XML is walked from bounded parser events without building a DOM; legacy HTML
uses the same HTML5 tree builder as the renderer. XML end-of-line handling and
HTML named entities match browser behavior, because CFI offsets must equal
browser DOM offsets.

Positions are deterministic: one per 1,024 UTF-16 code units of reading text in
each reflowable reading-order resource, rounded up, and exactly one for fixed
layout, text-free, non-text or unreadable resources. Non-linear resources have
no positions. Total progression interpolates positions, preserving every full
1,024-code-unit boundary and scaling a final short interval through its next
position boundary, so every resource is reachable and progress is monotonic.
Positions can be cached as JSON with a format version; caches validate every
resource's count, length and unreadable state as well as the reading order when
reused.

Search scans reading-order documents lazily, one document at a time, with a
bounded result count. Matching normalizes whitespace, soft hyphens and
zero-width spaces and optionally folds case and diacritics. Diacritic folding
uses a generated table from Unicode decomposition data for Latin, Greek,
Cyrillic, Arabic and Hebrew; kana and Indic marks are kept because they
distinguish words. Matches do not cross blocks. `SearchService` is an interface
so applications can substitute a persistent index built from `DocumentText`,
converting hits with `ReadingServices.locatorForTextRange`. No database is
added to the core.

`ReadingServices` keeps a small least-recently-used cache of parsed documents
and does not retain failures. Locators receive positions only after positions
are computed, because computing them parses the whole book. Restoration tries
CFI (accepted only when it agrees with the stored text), then the stored text
nearest to other estimates, fragments, progression, position and finally the
resource start, and returns a refreshed locator.
