# ADR 0002: Replaceable ZIP boundary with SDK decompression

Status: accepted after dependency inspection.

Expose our own Archive and ArchiveEntry. Implement only ZIP32 framing needed to
locate stored/Deflate resources, using Asset range reads and the Dart SDK raw
DEFLATE decoder. DEFLATE itself is not reimplemented. No extraction to disk.

We inspected archive 4.3.0 dependency metadata and local 4.2.0 and 3.6.1 source.
The current 4.x line brings posix/ffi transitively, violating the explicit no-FFI
constraint. The older 3.6.1 line avoids FFI, but its high-level decoder expands
symlinks before wrapper validation and its decompression path does not enforce
our output cap. Maintaining preflight guards around that old dependency would
still require framing checks. A narrow adapter with SDK decompression avoids
both an outdated codec dependency and implicit native bindings.

Check central-directory bounds before reading it, index lazily, validate names,
reject unsupported flags and formats, and bound actual decompressed output via
a chunked sink before appending bytes. Check declared length and CRC after read.
Use no indefinite entry cache. Compressed ranges may decode the entire entry.
File-backed assets remain random-access; no complete book allocation is needed.

Support ZIP32, single-disk, unencrypted, stored/Deflate entries initially. Reject
ZIP64 explicitly rather than partially interpreting it. This is an intentional
EPUB compatibility limitation: EPUB 3.3 permits ZIP64. Revisit with conformance
fixtures and an appropriate maintained pure-Dart backend before claiming broad
EPUB compatibility. Close invalidates access. EPUB mimetype placement and OCF
content checks belong to the deferred EPUB parser.
