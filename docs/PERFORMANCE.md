# Performance

Measured on 2026-09-24 with `packages/readpub/tool/benchmark.dart`, compiled with
`dart compile exe` (Dart 3.13.4), on an Apple M4 Pro (14 cores, 24 GB) running
macOS 27.0. Three consecutive runs differed by less than 2 ms per phase except
`open`, which ranged from 46 to 62 ms. Numbers depend on hardware; phones are
several times slower. Peak RSS is the process maximum so far, including the
Dart runtime and the benchmark's own allocations.

## Workload

`tool/generate_benchmark_epub.py` writes an original synthetic EPUB that is not
committed: 108.8 MB on disk, 300 XHTML chapters with about 3.6 million
characters of text (4,158 positions), 300 deflated incompressible 300 KB
images, a 20 MB stored audio member and a nested table of contents with 3,300
entries. Reproduce from `packages/readpub` with:

```sh
python3 tool/generate_benchmark_epub.py /tmp/benchmark.epub
dart compile exe tool/benchmark.dart -o /tmp/benchmark
/tmp/benchmark /tmp/benchmark.epub
```

## Results

| Phase | Time | Peak RSS | Notes |
|---|---:|---:|---|
| Open publication | 46–62 ms | 56 MB | 300 spine items, 302 resources, 3,300 TOC entries |
| Parse first chapter, cold | 6 ms | 59 MB | 14,129 characters |
| Compute positions | 160 ms | 65 MB | Parses all 300 chapters |
| Positions from JSON cache | 3 ms | 65 MB | Validated decode |
| Search, first match | < 1 ms | 65 MB | Stream stops after one result |
| Search whole book, common phrase | 420 ms | 75 MB | 1,100 results with locators and CFIs |
| Search whole book, no match | 226 ms | 81 MB | Every chapter parsed and folded |
| Locator create and resolve | 99 ms | 81 MB | 200 round trips, all resolved by CFI |
| Render preparation | 11 ms | 81 MB | 20 chapters |
| 20 range reads, deflated image | 11 ms | 97 MB | 64 KiB of a 300 KB member each |
| 20 range reads, stored audio | 20 ms | 97 MB | 64 KiB of a 20 MB member each |

Before ADR 0012, the last two phases took 156 ms and 9,787 ms, with peak RSS
rising to 121 MB, and positions and search were about 60 percent slower,
because every read CRC-checked the complete member with a bitwise CRC.

## Findings and decisions

- **Repeated decompression.** Stored members are verified once and then read by
  range. Deflated members are inflated per read, which costs about 0.5 ms for a
  300 KB member; a decompressed-member cache is not justified yet (ADR 0012).
- **Bounded caching.** `ReadingServices` keeps eight parsed documents. Whole-book
  services stream one document at a time, so memory stays flat as books grow;
  the growth above reflects allocator retention, not cached documents.
- **Synchronous CPU work.** The largest synchronous step is parsing one content
  document, 6 ms for 14,000 characters here, and parsing is linear in document
  size. Whole-book operations yield between documents. No isolate API is added.
  Applications that parse unusually large chapters, or need positions for many
  books at once, can run `ReadingServices` in their own isolate over a
  separately opened publication.
- **Positions.** Computing positions costs about one parse of the book, so
  applications should cache `PublicationPositions.toJson()` per publication.
- **Configured limits.** The defaults admitted this book. `ArchiveLimits`
  rejects members over 64 MB and books over 1 GB or 512 MB uncompressed;
  `ContentLimits` rejects content documents over 8 MB, 100,000 elements or
  depth 128. Larger media require explicit limits.

These measurements use synthetic content. Real-world profiling with licensed
large illustrated books and on target phones remains outstanding.
