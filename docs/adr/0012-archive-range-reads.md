# ADR 0012: Verify stored members once, then read ranges directly

Status: accepted and implemented after measurement.

ZIP range reads materialized, decompressed and CRC-checked the whole member on
every call, and CRC-32 was computed bit by bit. Browsers request media and
fonts in many byte ranges. On a 108.8 MB synthetic book, twenty 64 KiB ranges
of a 20 MB stored audio member took 9.8 seconds; the same ranges of a 300 KB
deflated image took 156 ms. See PERFORMANCE.md.

CRC-32 now uses slicing-by-eight tables. A stored member is still verified
completely on first access, including a first range request, so corrupt bytes
are never served; a first range request streams the verification in 1 MiB
chunks instead of materializing the member. After successful verification its
validated data offset is remembered and later reads fetch only the requested
bytes from the asset, relying on the existing requirement that inputs do not
change while open. Failed verification is not remembered. The same ranges now
take 20 ms and 11 ms, and peak memory no longer grows by the size of the
stored member.

Deflated members are still decompressed per read. Measured cost is about half a
millisecond per range for a 300 KB image, so a decompressed-member cache, with
its memory policy and invalidation, is not justified by current evidence.
Large media should be stored uncompressed, which EPUB packaging tools normally
do. Reconsider a bounded cache or streaming inflation if profiling of real
publications shows repeated large deflated reads.
