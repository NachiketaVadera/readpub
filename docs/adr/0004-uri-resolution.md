# ADR 0004: Keep URI references distinct from raw archive paths

Status: accepted; publication reference resolution amended by ADR 0013.

Raw ZIP filenames use case-sensitive slash-separated paths. Normalize benign dot
segments but reject traversal above root, absolute paths, backslashes, controls,
and collisions after normalization. A literal percent in a ZIP filename remains
literal. Never apply filesystem path rules or extract ZIP members to disk.

Publication references are local relative URIs. Resolve against a document path,
decode each segment once, reject malformed escapes and encoded separators, and
check containment before normalization can erase evidence of root escape.
Strip query and fragment only for byte lookup; preserve resource identity.
Reject schemes and authorities at the local fetcher boundary. No external URL
is fetched implicitly. Double decoding is forbidden.

This is a constrained archive URI profile, not a complete WHATWG URL parser.
Encoded separators and root-relative references are deliberately rejected for
an unambiguous storage boundary. Future EPUB URL handling, xml:base and remote
resource policy must be reconciled with W3C processing requirements separately.

Amendment (ADR 0013): EPUB Reading Systems 3.3 requires references in package,
navigation and content documents to resolve against a container root URL for
which `/` and `..` resolve to the root itself. Package and navigation references
therefore resolve against a synthetic container root: excess `..` segments stop
at the root and path-absolute references start there, with `url-leaks-container`
and `url-path-absolute` warnings. No reference can leave the container. The
archive-path and fetcher boundaries above remain strict; the render session
rewrites such content URLs so browsers resolve them inside the session path.
