# Independent ZIP fixture

`independent-python.zip` is a deterministic, original synthetic ZIP produced
with Python standard-library zipfile, independent of the Dart test ZIP builder.
It is not a complete EPUB (there is no OPF or container.xml).

Entries:

- `mimetype`: stored `application/epub+zip` bytes.
- `Text/chapter one.xhtml`: Deflate-compressed UTF-8 `<p>Café &amp; tea.</p>`.
- `literal%20.txt`: stored literal-percent filename, `literal percent` bytes.
- `Unicode/日本語.txt`: Deflate-compressed `言葉` UTF-8 text.

Timestamps are fixed at 2026-01-01 and permissions at regular file 0644.
Tests check stored/Deflate interoperability, space and Unicode lookup, and
percent-decoding exactly once. Content is authored for this repository and
covered by its BSD 3-Clause license.

`independent-descriptors.zip` uses an unseekable Python BytesIO writer so ZIP
bit 3 is set and sizes/CRC appear in signed data descriptors after each member.
It contains stored.txt (`stored descriptor`) and deflate.txt (`deflate descriptor`)
with the same fixed timestamp/permissions. This verifies a ZIP writer independent
of the library's framing implementation.
