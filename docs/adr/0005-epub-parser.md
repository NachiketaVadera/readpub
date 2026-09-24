# ADR 0005: EPUB normalization and safe XML parsing

Status: accepted before parser implementation; recovery rules amended by ADR 0013.

Use a bounded XML boundary, separate OPF metadata/manifest/spine and navigation
parsers, and return an immutable format-independent Publication. Resource bytes
remain behind Fetcher; parsers do not return ZIP or XML internals to consumers.
Keep raw metadata records to retain unknown vocabulary values and refinements.

EPUB2 and EPUB3 share container/OPF processing; namespace URIs determine meaning,
not chosen prefixes. EPUB3 XHTML nav takes priority over NCX; legacy guide maps
to landmarks. Resolve references against the containing document and inherited
xml:base. Preserve tree structure, linearity, rendition and progression.

Recovery applies to noncritical metadata and optional navigation only. Invalid
container/package structure, duplicate ambiguous manifest identifiers, unsafe
paths, recursive fallback chains and encryption corruption are fatal. After the
W3C conformance run (ADR 0013), unknown package versions, missing spine files
and container-leaking URLs are diagnosed rather than fatal. Remote
HTTP(S) links may be retained as references but are never fetched by the local
publication. Unsupported encrypted resource access fails rather than returning
unusable encrypted bytes.

Use current pure-Dart xml and crypto dependencies, with no framework or native
bindings. Reject entity definitions before parsing; tolerate a bare historical
XHTML/NCX doctype without resolving its external subset. Byte/depth/node limits
bound XML work; no external entity/network resolver is installed.

Keep compliance claims tied to fixtures and document compatibility deviations.
ZIP64 remains an independent archive limitation, not a reason to mislabel
supported EPUB2/3 package structures as entirely unsupported.
