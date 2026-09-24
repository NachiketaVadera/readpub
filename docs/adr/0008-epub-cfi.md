# ADR 0008: A grammar-based EPUB CFI model with explicit resolution

Status: accepted and implemented.

EPUB CFI 1.1 defines a grammar, escaping, sorting rules, ranges and
indirection. String splitting cannot validate escapes, assertions or offsets and
cannot compare locations. Implement a recursive-descent parser that produces an
immutable syntax tree (`EpubCfi`, `CfiPath`, `CfiStep`, `CfiOffset`), a canonical
serializer and a comparator implementing the specification sorting rules.
Parsing is strict: leading zeros, non-canonical fractions, bad escapes, empty
assertions, text assertions outside character offsets, reversed ranges and
range parents ending in offsets are rejected with the failing source offset.
Input length is bounded because CFIs arrive from renderers and storage.

The syntax model knows nothing about documents. A step marked as an
indirection separates the package path from the content-document path.
`EpubPublication.spine` records the package coordinates of every itemref,
including non-linear items and foreign elements that shift indices, so
publication CFIs are generated and resolved without re-reading the OPF.

Content resolution is defined by `DocumentText`: steps count element children
and character-data chunks as the specification requires, comments and
processing instructions are ignored, CDATA is character data and offsets are
UTF-16 code units. Virtual first and last child positions are supported. ID
assertions correct moved elements; text assertions correct moved offsets by
the nearest matching text. When an assertion fails and cannot be corrected the
CFI is invalid, as the specification requires. Offsets beyond a chunk are
clamped and reported as approximate rather than rejected, because restoration
prefers a nearby location to none. Indirection inside content documents stops
at the referencing element. Itemref assertions that name a manifest ID, as some
reading systems write, are accepted as corrections.
