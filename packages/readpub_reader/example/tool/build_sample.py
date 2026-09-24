"""Build the example app's original sample book, The Lantern Keeper.

The text is original and released with this repository under its BSD 3-Clause
license. Output: example/assets/lantern-keeper.epub, rebuilt byte for byte.
"""
from pathlib import Path
import struct
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/lantern-keeper.epub"
DATE = (2026, 9, 24, 0, 0, 0)
XHTML = "http://www.w3.org/1999/xhtml"
EPUB = "http://www.idpf.org/2007/ops"

CHAPTERS = [
    ("The Lighthouse at Harrow Point", [
        "Mara Venn arrived at Harrow Point on the last ferry of October, with a trunk of borrowed books and a letter of appointment that the wind tried twice to take from her hand. The lighthouse stood at the end of a long finger of rock, white paint gone grey where the salt had worked at it, and the lantern room at the top caught the low sun like a second, smaller sunset.",
        "The retiring keeper, a narrow man named Osric Hale, met her at the landing with a lantern of his own, unlit. He did not ask about the crossing. He asked whether she could climb one hundred and twelve steps in the dark without counting them, because counting, he said, was how people lost their footing.",
        "She said she did not know. He nodded as though that were the correct answer and handed her the lantern. Inside, the tower smelled of paraffin and cold stone and something sweeter underneath, like apples kept too long in a cellar. The stairs turned to the left, always to the left, until the turning became a kind of weather she stopped noticing.",
        "At the top, Osric showed her the great lens: tier upon tier of glass prisms folded around a flame no larger than a thumb. It is not the fire that saves ships, he told her. It is the glass. The fire only has to be honest; the glass makes it loud.",
        "That night she slept in the keeper's room below the gallery, and dreamed of harbours she had never seen, each one lit by a single window left open for her.",
    ]),
    ("A Letter from the Mainland", [
        "The supply boat came every second Thursday, weather permitting, which meant that in winter it came when it liked. It brought flour, oil, wicks, a newspaper already a week old, and once, wrapped in oilcloth, a letter addressed to the keeper in handwriting Mara did not recognise.",
        "Osric had left by then. He had stayed three days to teach her the lamp and the log and the particular cough of the clockwork that turned the lens, and on the fourth morning he had simply been gone, his bunk made with military corners, a note on the table that read only: Trim the wick before you trust it.",
        "The letter was from a woman named Ilse Carrow, who wrote that her brother had been lost off Harrow Point eleven years before, on a night when the light had failed. She did not accuse anyone. She asked only whether the log for that night still existed, and whether the new keeper would be kind enough to copy one line from it.",
        "Mara found the old logs in a cabinet that stuck in damp weather. The entries were in Osric's cramped hand, the same notes repeated with small variations for years: wind, visibility, oil used, ships sighted. On the night Ilse named, the entry was longer than any other, and it had been written, as far as Mara could tell, twice.",
    ]),
    ("The Winter Storm", [
        "The storm came in the second week of December and stayed for four days. The sea stood up on its hind legs and walked into the rocks. Spray reached the gallery rail, one hundred feet above the tide, and froze there in long glass fingers that rang when the wind moved them.",
        "Mara did not sleep. She trimmed the wick every hour and wound the clockwork every four, and between those tasks she read the double entry by lamplight until she knew both versions by heart. In the first, the light had failed at midnight when the clockwork jammed. In the second, the light had burned all night, and a small boat had been seen standing too close to the point, and had not answered the horn.",
        "On the third night the clockwork jammed. She heard it before she understood it: a hitch in the familiar rhythm, a grinding, then a silence much larger than the room. The lens stopped turning. The flame still burned, but a steady light is not a lighthouse; to a ship it is only a window, and windows do not warn anyone of rocks.",
        "She found the fault by feel, a sliver of ice that had crept in through a seam and wedged itself between two teeth of the great gear. She warmed it out with her own hands and the lamp's chimney, burning two fingers badly enough that she would carry the marks for the rest of her life. Then she turned the lens by hand until the gear would take it again. It was the longest hour she ever spent.",
        "When the grey light came up at last, she went out onto the gallery and saw a fishing boat riding safe in the lee of the point, her crew waving their caps at the tower as though it could see them.",
    ]),
    ("What the Keeper Kept", [
        "In spring she wrote to Ilse Carrow and told her the truth, which was that she did not know which entry was true. She copied both lines, exactly, and added a third of her own: that the clockwork at Harrow Point jammed in hard frost, and that a keeper alone in a storm could keep the light turning, but not easily, and not without cost.",
        "Two months later a small parcel came on the supply boat. Inside was a photograph of a young man in a fisherman's jersey, laughing at something outside the frame, and a note in the same careful handwriting: Thank you for not choosing for me.",
        "Mara set the photograph on the shelf beside the log cabinet. Later that summer, painting the lantern room, she found a tin box hidden behind a loose board under the lens: a child's compass, a folded map of the point with the rocks marked in red, and a scrap of paper in Osric's hand.",
        "The paper said: The first entry is what the log required. The second is what I saw. Keep whichever lets you climb the stairs.",
    ], "The keeper's second entry", [
        "She understood then why the second entry had been written. A keeper is not a witness. A keeper is the person who stays when the witnesses have gone home, and who keeps the light honest so that the glass can make it loud.",
    ]),
    ("The Last Lamp", [
        "The electric lamp came to Harrow Point nine years after Mara did. Engineers arrived with cables and a generator and a new lens of moulded plastic that turned on its own and needed no winding. They were polite about the old lens, the way people are polite about the dead.",
        "On the last night before the changeover she lit the paraffin flame one more time and climbed the stairs without counting them. The prisms took the small honest fire and made it loud, as they had for a hundred years, and she stood in the gallery wind watching the beam go out across the water: a white arm, then darkness, then the white arm again.",
        "Somewhere out there, she thought, a boat was steering by it, and would never know that this was the last time. That seemed right to her. The best lights are the ones nobody has to think about.",
        "In the morning she wrote a single line in the log, closed it, and left it in the cabinet for whoever came after. Then she packed her trunk of borrowed books, which had grown into a trunk of her own, and walked down to the landing to wait for the ferry.",
    ]),
]


def paragraphs(items, prefix):
    return "".join(f'<p id="{prefix}-{i + 1}">{text}</p>\n' for i, text in enumerate(items))


def chapter(number, title, body, section=None):
    notes = ""
    if number == 2:
        body = body[:]
        body[2] = body[2].replace(
            "eleven years before",
            'eleven years before<a epub:type="noteref" id="ref1" href="notes.xhtml#n1">1</a>',
        )
    section_html = ""
    if section:
        section_html = f'<h2 id="c{number}-s">{section[0]}</h2>\n' + paragraphs(section[1], f"c{number}-s")
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>\n<html xmlns="{XHTML}" xmlns:epub="{EPUB}" xml:lang="en">\n'
        f'<head><title>{title}</title><link rel="stylesheet" href="../Styles/book.css"/></head>\n'
        f'<body>\n<section epub:type="chapter">\n<h1 id="c{number}">{number}. {title}</h1>\n'
        + paragraphs(body, f"c{number}")
        + section_html
        + "</section>\n</body>\n</html>\n"
        + notes
    )


def png(width, height):
    """A deep-blue cover with a warm lantern-colored band."""
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            glow = max(0, 1 - abs(y - height * 0.42) / (height * 0.12)) * max(0, 1 - abs(x - width / 2) / (width * 0.35))
            r = int(24 + 231 * glow)
            g = int(38 + 170 * glow)
            b = int(72 + 20 * glow)
            row += bytes((r, g, b))
        rows.append(bytes(row))
    raw = zlib.compress(b"".join(rows), 9)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", raw) + chunk(b"IEND", b""))


def main():
    files = {
        "mimetype": "application/epub+zip",
        "META-INF/container.xml": '<?xml version="1.0"?>\n<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>\n',
        "OEBPS/Styles/book.css": "body { font-family: Georgia, serif; } h1 { font-size: 1.4em; margin: 1.5em 0 1em; } h2 { font-size: 1.1em; } p { text-indent: 1.4em; margin: 0 0 0.4em; text-align: justify; } p:first-of-type { text-indent: 0; } .cover { text-align: center; } .cover img { max-height: 90vh; } a[epub|type~='noteref'] { vertical-align: super; font-size: 0.7em; }\n",
        "OEBPS/Images/cover.png": png(300, 450),
        "OEBPS/Text/cover.xhtml": f'<?xml version="1.0" encoding="UTF-8"?>\n<html xmlns="{XHTML}" xml:lang="en"><head><title>Cover</title><link rel="stylesheet" href="../Styles/book.css"/></head><body><div class="cover"><img src="../Images/cover.png" alt="The Lantern Keeper"/></div></body></html>\n',
        "OEBPS/Text/notes.xhtml": f'<?xml version="1.0" encoding="UTF-8"?>\n<html xmlns="{XHTML}" xmlns:epub="{EPUB}" xml:lang="en"><head><title>Notes</title><link rel="stylesheet" href="../Styles/book.css"/></head><body><aside epub:type="footnote" id="n1"><p>1. Harrow Point records from that decade survive only in the keeper\'s own logs. <a href="chapter-2.xhtml#ref1">Return</a></p></aside></body></html>\n',
        "OEBPS/Text/colophon.xhtml": f'<?xml version="1.0" encoding="UTF-8"?>\n<html xmlns="{XHTML}" xml:lang="en"><head><title>Colophon</title><link rel="stylesheet" href="../Styles/book.css"/></head><body><h1 id="colophon">Colophon</h1><p>The Lantern Keeper is an original sample book for the readpub_reader example. It is released under the BSD 3-Clause license.</p><p>More about EPUB: <a href="https://www.w3.org/publishing/epub3/">W3C EPUB 3</a>.</p></body></html>\n',
    }
    for number, entry in enumerate(CHAPTERS, 1):
        title, body = entry[0], entry[1]
        section = (entry[2], entry[3]) if len(entry) > 2 else None
        files[f"OEBPS/Text/chapter-{number}.xhtml"] = chapter(number, title, body, section)
    toc = ['<li><a href="Text/cover.xhtml">Cover</a></li>']
    for number, entry in enumerate(CHAPTERS, 1):
        child = f'<ol><li><a href="Text/chapter-{number}.xhtml#c{number}-s">{entry[2]}</a></li></ol>' if len(entry) > 2 else ""
        toc.append(f'<li><a href="Text/chapter-{number}.xhtml#c{number}">{number}. {entry[0]}</a>{child}</li>')
    toc.append('<li><a href="Text/colophon.xhtml">Colophon</a></li>')
    files["OEBPS/nav.xhtml"] = (f'<?xml version="1.0" encoding="UTF-8"?>\n<html xmlns="{XHTML}" xmlns:epub="{EPUB}" xml:lang="en"><head><title>Contents</title></head>'
                                f'<body><nav epub:type="toc"><h1>Contents</h1><ol>{"".join(toc)}</ol></nav></body></html>\n')
    manifest = [
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
        '<item id="css" href="Styles/book.css" media-type="text/css"/>',
        '<item id="cover-image" href="Images/cover.png" media-type="image/png" properties="cover-image"/>',
        '<item id="cover" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>',
        '<item id="notes" href="Text/notes.xhtml" media-type="application/xhtml+xml"/>',
        '<item id="colophon" href="Text/colophon.xhtml" media-type="application/xhtml+xml"/>',
    ]
    spine = ['<itemref idref="cover" linear="yes"/>']
    for number in range(1, len(CHAPTERS) + 1):
        manifest.append(f'<item id="chapter-{number}" href="Text/chapter-{number}.xhtml" media-type="application/xhtml+xml"/>')
        spine.append(f'<itemref idref="chapter-{number}" id="ref-chapter-{number}"/>')
    spine.append('<itemref idref="notes" linear="no"/>')
    spine.append('<itemref idref="colophon"/>')
    files["OEBPS/package.opf"] = (
        '<?xml version="1.0" encoding="UTF-8"?>\n<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="en">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">urn:uuid:5f0c3a2e-7d1b-4c57-9e0a-6b1f2d3c4e5f</dc:identifier>'
        '<dc:title>The Lantern Keeper</dc:title><dc:creator>readpub contributors</dc:creator><dc:language>en</dc:language>'
        '<dc:rights>BSD 3-Clause</dc:rights><meta property="dcterms:modified">2026-09-24T00:00:00Z</meta></metadata>'
        f'<manifest>{"".join(manifest)}</manifest><spine>{"".join(spine)}</spine></package>\n'
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w") as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo(name, date_time=DATE)
            info.compress_type = zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data.encode("utf-8") if isinstance(data, str) else data)
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


main()
