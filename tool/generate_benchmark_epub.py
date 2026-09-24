"""Generate a large, original synthetic EPUB for performance measurement.

The output is written outside the repository fixtures and is not committed.
Usage: python3 tool/generate_benchmark_epub.py OUT.epub [chapters]

Defaults produce about 3.6 million characters of text in 300 chapters, 300
deflated incompressible 300 KB images, a 20 MB stored audio file and a nested
table of contents with 3,300 entries.
"""
from pathlib import Path
import random
import sys
import zipfile

OUT = Path(sys.argv[1])
CHAPTERS = int(sys.argv[2]) if len(sys.argv) > 2 else 300
SECTIONS = 10
PARAGRAPHS = 40
XHTML = "http://www.w3.org/1999/xhtml"
EPUB = "http://www.idpf.org/2007/ops"
WORDS = ("harbor lantern voyage northern tide compass orchard meadow river "
         "quiet signal winter pebble cedar amber thunder whisper canyon "
         "saffron glacier velvet ember mosaic").split()
rng = random.Random(1729)


def paragraph(index):
    words = [rng.choice(WORDS) for _ in range(rng.randint(35, 60))]
    words[0] = words[0].capitalize()
    return f'<p id="p{index}">{" ".join(words)}.</p>\n'


def chapter(number):
    parts = [f'<?xml version="1.0" encoding="UTF-8"?>\n<html xmlns="{XHTML}"><head>'
             f'<title>Chapter {number}</title></head><body>\n<h1 id="c{number}">Chapter {number}</h1>\n']
    for section in range(SECTIONS):
        parts.append(f'<h2 id="s{section}">Section {number}.{section}</h2>\n')
        for p in range(PARAGRAPHS // SECTIONS):
            parts.append(paragraph(section * 100 + p))
    parts.append(f'<p><img src="../Images/i{number}.jpg" alt="Plate {number}"/></p></body></html>')
    return "".join(parts)


def main():
    manifest, spine, toc = [], [], []
    files = {}
    for number in range(1, CHAPTERS + 1):
        files[f"OEBPS/Text/c{number}.xhtml"] = chapter(number)
        files[f"OEBPS/Images/i{number}.jpg"] = rng.randbytes(300 * 1024)
        manifest.append(f'<item id="c{number}" href="Text/c{number}.xhtml" media-type="application/xhtml+xml"/>')
        manifest.append(f'<item id="i{number}" href="Images/i{number}.jpg" media-type="image/jpeg"/>')
        spine.append(f'<itemref idref="c{number}"/>')
        sections = "".join(
            f'<li><a href="Text/c{number}.xhtml#s{s}">Section {number}.{s}</a></li>' for s in range(SECTIONS))
        toc.append(f'<li><a href="Text/c{number}.xhtml#c{number}">Chapter {number}</a><ol>{sections}</ol></li>')
    files["OEBPS/Audio/track.mp3"] = rng.randbytes(20 * 1024 * 1024)
    manifest.append('<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>')
    manifest.append('<item id="audio" href="Audio/track.mp3" media-type="audio/mpeg"/>')
    files["OEBPS/nav.xhtml"] = (f'<html xmlns="{XHTML}" xmlns:epub="{EPUB}"><head><title>Contents</title></head>'
                                f'<body><nav epub:type="toc"><ol>{"".join(toc)}</ol></nav></body></html>')
    files["OEBPS/package.opf"] = (
        '<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'version="3.0" unique-identifier="uid"><metadata><dc:identifier id="uid">urn:uuid:benchmark</dc:identifier>'
        '<dc:title>Benchmark</dc:title><dc:language>en</dc:language></metadata>'
        f'<manifest>{"".join(manifest)}</manifest><spine>{"".join(spine)}</spine></package>')
    container = ('<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles>'
                 '<rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    with zipfile.ZipFile(OUT, "w") as archive:
        archive.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
        archive.writestr("META-INF/container.xml", container, zipfile.ZIP_DEFLATED)
        for name, data in files.items():
            method = zipfile.ZIP_STORED if name.endswith(".mp3") else zipfile.ZIP_DEFLATED
            archive.writestr(name, data, method)
    print(f"Wrote {OUT} ({OUT.stat().st_size / 1024 / 1024:.1f} MB, {CHAPTERS} chapters)")


main()
