"""Generate original, deterministic EPUB parser fixtures using Python stdlib."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1] / "test/fixtures/epub"
OCF = "urn:oasis:names:tc:opendocument:xmlns:container"
OPF = "http://www.idpf.org/2007/opf"
DC = "http://purl.org/dc/elements/1.1/"
XHTML = "http://www.w3.org/1999/xhtml"
EPUB = "http://www.idpf.org/2007/ops"
UID = "urn:uuid:12345678-1234-1234-1234-123456789abc"
CONTAINER = f'<container xmlns="{OCF}" version="1.0"><rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
CHAPTER = f'<html xmlns="{XHTML}"><head><title>Chapter</title></head><body><h1 id="start">Hello</h1><p>Original fixture text.</p></body></html>'
NAV = f'<html xmlns="{XHTML}" xmlns:epub="{EPUB}"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="Text/chapter%20one.xhtml#start">Chapter One</a></li></ol></nav></body></html>'

def package(version="3.0", metadata="", manifest="", spine="", tail="", attrs=""):
    return f'<package xmlns="{OPF}" xmlns:dc="{DC}" version="{version}" unique-identifier="uid" {attrs}><metadata><dc:identifier id="uid">{UID}</dc:identifier><dc:title>Fixture</dc:title><dc:language>en</dc:language>{metadata}</metadata><manifest><item id="chapter" href="Text/chapter%20one.xhtml" media-type="application/xhtml+xml"/>{manifest}</manifest><spine {spine}><itemref idref="chapter"/></spine>{tail}</package>'

def write(name, opf, extra=None, container=CONTAINER):
    files={"mimetype":"application/epub+zip","META-INF/container.xml":container,"OEBPS/package.opf":opf,"OEBPS/Text/chapter one.xhtml":CHAPTER}
    files.update(extra or {})
    ROOT.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(ROOT/name,"w") as z:
        for name,data in files.items():
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0))
            info.compress_type=zipfile.ZIP_STORED if name=="mimetype" else zipfile.ZIP_DEFLATED
            info.external_attr=0o100644 << 16
            z.writestr(info,data.encode("utf-8") if isinstance(data,str) else data)

write("epub3-basic.epub",package(manifest='<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'),{"OEBPS/nav.xhtml":NAV})
rich_meta='''<dc:title id="main" xml:lang="en">Example &amp; World</dc:title><meta refines="#main" property="title-type">main</meta><dc:title id="sub">A Subtitle</dc:title><meta refines="#sub" property="title-type">subtitle</meta><dc:creator id="author">Ada Author</dc:creator><meta refines="#author" property="role" scheme="marc:relators">aut</meta><meta refines="#author" property="file-as">Author, Ada</meta><dc:contributor id="editor">Ed Editor</dc:contributor><meta refines="#editor" property="role" scheme="marc:relators">edt</meta><dc:contributor id="translator">Tia Translator</dc:contributor><meta refines="#translator" property="role">trl</meta><dc:publisher>Example Press</dc:publisher><dc:language>fr</dc:language><dc:subject id="topic">Computing</dc:subject><meta refines="#topic" property="authority">BISAC</meta><meta refines="#topic" property="term">COM000000</meta><dc:description>Original description.</dc:description><dc:rights>Fixture rights</dc:rights><dc:date>2024-05-06</dc:date><meta property="dcterms:modified">2025-01-02T03:04:05Z</meta><meta property="rendition:layout">pre-paginated</meta><meta property="rendition:orientation">landscape</meta><meta property="rendition:spread">both</meta><meta property="media:duration">01:02:03.5</meta><meta property="media:duration" refines="#overlay">12.25s</meta><meta property="schema:accessMode">textual</meta><meta property="schema:accessibilityFeature">tableOfContents</meta><meta property="schema:numberOfPages">123</meta><meta property="x:note" id="custom">retained</meta>'''
rich_manifest='''<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="appendix" href="Text/appendix.xhtml" media-type="application/xhtml+xml"/><item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/><item id="overlay" href="overlay.smil" media-type="application/smil+xml"/><item id="foreign" href="foreign.bin" media-type="application/x-example" fallback="chapter"/><item id="handler" href="handler.xhtml" media-type="application/xhtml+xml" properties="scripted"/>'''
rich=package(metadata=rich_meta,manifest=rich_manifest,spine='page-progression-direction="rtl"',attrs='prefix="x: https://example.org/vocab/"',tail='<bindings><mediaType media-type="application/x-example" handler="handler"/></bindings><collection role="preview"><link href="Text/chapter%20one.xhtml" rel="preview"/><collection role="nested"><link href="cover.jpg"/></collection></collection>')
rich=rich.replace('<itemref idref="chapter"/>','<itemref idref="chapter" properties="page-spread-left rendition:orientation-portrait"/><itemref idref="appendix" linear="no"/>').replace('id="chapter" href=','id="chapter" media-overlay="overlay" href=')
rich_nav=f'<html xmlns="{XHTML}" xmlns:epub="{EPUB}"><head><title>Contents</title></head><body><nav epub:type="toc lot"><ol><li><span>Part One</span><ol><li><a href="Text/chapter%20one.xhtml?q=1#start">Chapter <em>One</em></a></li></ol></li></ol></nav><nav epub:type="landmarks"><ol><li><a epub:type="bodymatter" href="Text/chapter%20one.xhtml">Start</a></li></ol></nav><nav epub:type="page-list"><ol><li><a href="Text/chapter%20one.xhtml#p1">1</a></li></ol></nav></body></html>'
write("epub3-rich.epub",rich,{"OEBPS/nav.xhtml":rich_nav,"OEBPS/Text/appendix.xhtml":CHAPTER,"OEBPS/cover.jpg":b"\xff\xd8\xff\xd9","OEBPS/overlay.smil":'<smil xmlns="http://www.w3.org/ns/SMIL" version="3.0"><body/></smil>',"OEBPS/foreign.bin":b"foreign","OEBPS/handler.xhtml":CHAPTER})
ncx='''<?xml version="1.0"?><!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd"><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>Legacy</text></docTitle><navMap><navPoint id="part"><navLabel><text>Part</text></navLabel><content src="Text/chapter%20one.xhtml"/><navPoint id="c1"><navLabel><text>Chapter One</text></navLabel><content src="Text/chapter%20one.xhtml#start"/></navPoint></navPoint></navMap><pageList><pageTarget id="p1" type="normal" value="1"><navLabel><text>1</text></navLabel><content src="Text/chapter%20one.xhtml#p1"/></pageTarget></pageList></ncx>'''
epub2=package(version="2.0",metadata='<dc:creator xmlns:opf="http://www.idpf.org/2007/opf" opf:role="aut" opf:file-as="Author, Legacy">Legacy Author</dc:creator><meta name="cover" content="cover"/>',manifest='<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="cover" href="cover.jpg" media-type="image/jpeg"/>',spine='toc="ncx"',tail='<guide><reference type="text" title="Start" href="Text/chapter%20one.xhtml#start"/></guide>')
write("epub2-ncx.epub",epub2,{"OEBPS/toc.ncx":ncx,"OEBPS/cover.jpg":b"cover"})
base=package(manifest='<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',attrs='xml:base="Content/"').replace("<manifest>",'<manifest xml:base="../Assets/">')
write("xml-base.epub",base,{"OEBPS/Assets/Text/chapter one.xhtml":CHAPTER,"OEBPS/Assets/nav.xhtml":NAV})
for name,opf in {
 "broken-spine.epub":package().replace('idref="chapter"','idref="missing"'),
 "duplicate-manifest.epub":package(manifest='<item id="chapter" href="other.xhtml" media-type="application/xhtml+xml"/>'),
 "unsafe-path.epub":package().replace("Text/chapter%20one.xhtml","../../outside.xhtml"),
 "fallback-cycle.epub":package(manifest='<item id="loop" href="loop.bin" media-type="application/x-loop" fallback="chapter"/>').replace('id="chapter" href=','id="chapter" fallback="loop" href='),
 "missing-nav.epub":package(manifest='<item id="nav" href="absent.xhtml" media-type="application/xhtml+xml" properties="nav"/>'),
 "remote-resource.epub":package(manifest='<item id="remote" href="https://example.invalid/audio.mp3" media-type="audio/mpeg"/>'),
 "entity-attack.epub":'<!DOCTYPE package [<!ENTITY leak SYSTEM "file:///etc/passwd">]>'+package(metadata="<dc:description>&leak;</dc:description>"),
 "foreign-namespace.epub":package().replace('<manifest>','<manifest xmlns="urn:foreign">'),
}.items():write(name,opf)
plain=bytes(i%251 for i in range(1300))
for label,algorithm,key,limit in [
 ("idpf","http://www.idpf.org/2008/embedding",hashlib.sha1(UID.encode()).digest(),1040),
 ("adobe","http://ns.adobe.com/pdf/enc#RC",bytes.fromhex(UID.removeprefix("urn:uuid:").replace("-","")),1024),
 ("unsupported","urn:example:unsupported",bytes([0]),0),
]:
 font=bytes(c^key[i%len(key)] if i<limit else c for i,c in enumerate(plain))
 enc=f'<encryption xmlns="{OCF}"><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="{algorithm}"/><CipherData><CipherReference URI="OEBPS/font.otf"/></CipherData></EncryptedData></encryption>'
 write(f"font-{label}.epub",package(manifest='<item id="font" href="font.otf" media-type="font/otf"/>'),{"OEBPS/font.otf":font,"META-INF/encryption.xml":enc})
# Additional parser boundaries and interoperability regressions.
nav_item = '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
write('unsafe-nav.epub', package(manifest=nav_item), {'OEBPS/nav.xhtml': NAV.replace('Text/chapter%20one.xhtml#start', '../../../escape')})
write('nav-ncx-fallback.epub', epub2.replace('</manifest>', nav_item+'</manifest>'), {'OEBPS/nav.xhtml': '<broken>', 'OEBPS/toc.ncx': ncx, 'OEBPS/cover.jpg': b'cover'})
write('utf16.epub', ('<?xml version="1.0" encoding="UTF-16"?>'+package(metadata='<dc:description>Café 雪</dc:description>')).encode('utf-16'))
write('encoded-root.epub', package(), {'OEBPS/100% book.opf': package()}, container=CONTAINER.replace('OEBPS/package.opf', 'OEBPS/100% book.opf'))
write('literal-percent.epub', package().replace('Text/chapter%20one.xhtml', 'Text/100%25%20雪.xhtml'), {'OEBPS/Text/100% 雪.xhtml': CHAPTER})
write('missing-metadata.epub', package().replace('<dc:title>Fixture</dc:title>', '').replace('<dc:language>en</dc:language>', ''))
write('invalid-date.epub', package(metadata='<dc:date>2024-02-31</dc:date><meta property="media:duration">banana</meta>'))
render_manifest = '<item id="css" href="Styles/book.css" media-type="text/css"/><item id="image" href="Images/cover.png" media-type="image/png"/>'
render_chapter = f'<html xmlns="{XHTML}"><head><title>Render test</title><base href="https://example.invalid/"/><link rel="stylesheet" href="../Styles/book.css"/><script>alert(1)</script></head><body onload="alert(2)"><h1 id="start">Render me</h1><img src="../Images/cover.png" alt="Cover"/></body></html>'
write('render-assets.epub',package(manifest=render_manifest),{
 "OEBPS/Text/chapter one.xhtml":render_chapter,
 "OEBPS/Styles/book.css":'body { background-image: url("../Images/cover.png"); }',
 "OEBPS/Images/cover.png":b"\x89PNG\r\n\x1a\n",
})
legacy_html='<html><head><title>Legacy</title><meta charset=windows-1252><meta http-equiv=" Refresh " content="0;url=https://example.invalid"><base href="https://example.invalid/"><script>alert(1)</script></head><body onload="alert(2)"><p>Unclosed paragraph<p>Second &amp; third — here</body></html>'
write('render-html.epub',package(version="2.0").replace('application/xhtml+xml', 'text/html').replace('Text/chapter%20one.xhtml','Text/chapter.html'),{
 "OEBPS/Text/chapter.html":legacy_html.encode("cp1252"),
})
write('render-utf16.epub', package(), {
 "OEBPS/Text/chapter one.xhtml": ('<?xml version="1.0" encoding="UTF-16"?>'+CHAPTER.replace('Hello', 'Café 雪')).encode('utf-16'),
})
write('render-override.epub', package(metadata='<meta property="rendition:layout">pre-paginated</meta>').replace('<itemref idref="chapter"/>','<itemref idref="chapter" properties="rendition:layout-reflowable"/>'))
# Reading services: text, positions, locators, CFI and search.
def paragraphs(first, count, extra):
    return "".join(
        f'<p id="p{first + i}">Paragraph {first + i} tells of a voyage across the northern sea.{extra.get(first + i, "")}</p>\r\n'
        for i in range(count)
    )
reading_ch1 = (f'<?xml version="1.0" encoding="UTF-8"?>\r\n<html xmlns="{XHTML}" xmlns:epub="{EPUB}" xml:lang="en"><head><title>One</title></head>\r\n<body>\r\n'
    '<h1 id="c1">Chapter One</h1>\r\n'
    + paragraphs(1, 20, {7: ' A <em>caf&eacute;</em> served na&#239;ve travellers.', 12: ' A whale surfaced.'})
    + '<h2 id="s2">Second Section</h2>\r\n'
    + paragraphs(21, 20, {30: ' The whale dived again.'})
    + '</body></html>')
reading_ch2 = (f'<html xmlns="{XHTML}"><head><title>Two</title></head><body><h1 id="c2">Chapter Two</h1>'
    '<p>Call the WHALE by name; whales are many.</p><p>Ishmael watched.</p></body></html>')
reading_notes = f'<html xmlns="{XHTML}"><head><title>Notes</title></head><body><p id="n1">A note about the whale.</p></body></html>'
reading_plate = f'<html xmlns="{XHTML}"><head><title>Plate</title><meta name="viewport" content="width=600, height=800"/></head><body><img src="plate.png" alt="Plate"/><p>Plate caption</p></body></html>'
reading_nav = (f'<html xmlns="{XHTML}" xmlns:epub="{EPUB}"><head><title>Contents</title></head><body><nav epub:type="toc"><ol>'
    '<li><a href="Text/one.xhtml#c1">Chapter One</a><ol><li><a href="Text/one.xhtml#s2">Second Section</a></li></ol></li>'
    '<li><a href="Text/two.xhtml">Chapter Two</a></li><li><a href="Text/plate.xhtml">Plate</a></li></ol></nav></body></html>')
reading_opf = (f'<package xmlns="{OPF}" xmlns:dc="{DC}" version="3.0" unique-identifier="uid"><metadata>'
    f'<dc:identifier id="uid">{UID}</dc:identifier><dc:title>Reading Fixture</dc:title><dc:language>en</dc:language></metadata><manifest>'
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
    '<item id="ch1" href="Text/one.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="notes" href="Text/notes.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="ch2" href="Text/two.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="plate" href="Text/plate.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="plate-image" href="Text/plate.png" media-type="image/png"/>'
    '<item id="broken" href="Text/broken.xhtml" media-type="application/xhtml+xml"/>'
    '</manifest><spine><itemref idref="ch1" id="ref-ch1"/><itemref idref="notes" linear="no"/><itemref idref="ch2"/>'
    '<itemref idref="plate" properties="rendition:layout-pre-paginated"/><itemref idref="broken"/></spine></package>')
files = {"mimetype": "application/epub+zip", "META-INF/container.xml": CONTAINER, "OEBPS/package.opf": reading_opf,
         "OEBPS/nav.xhtml": reading_nav, "OEBPS/Text/one.xhtml": reading_ch1, "OEBPS/Text/notes.xhtml": reading_notes,
         "OEBPS/Text/two.xhtml": reading_ch2, "OEBPS/Text/plate.xhtml": reading_plate, "OEBPS/Text/plate.png": b"\x89PNG\r\n\x1a\n",
         "OEBPS/Text/broken.xhtml": f'<html xmlns="{XHTML}"><body><p>unclosed</body></html>'}
with zipfile.ZipFile(ROOT / "reading.epub", "w") as z:
    for name, data in files.items():
        info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        z.writestr(info, data.encode("utf-8") if isinstance(data, str) else data)
# Renderer structure preservation: prepared documents keep CFI structure.
structure_xhtml = ('\ufeff<?xml version="1.0" encoding="UTF-8"?>\r\n'
    '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\r\n'
    f'<html xmlns="{XHTML}"><head><title>Structure</title><script>var a = 1;</script></head>\r\n<body>\r\n'
    '<p id="a">One&nbsp;&mdash; two</p>\r\n<script src="x.js"></script>\r\n'
    '<p>Three <iframe id="frame" src="x.html">fallback</iframe> four</p>\r\n'
    '<svg xmlns="http://www.w3.org/2000/svg"><script>y()</script><text>Svg</text></svg>\r\n'
    '<object data="x.svg"><p>fallback object</p></object><p onclick="z()">Five</p>\r\n</body></html>')
structure_headless = f'<html xmlns="{XHTML}"><body><p>No head</p></body></html>'
structure_html = ('<!DOCTYPE html><html><head><meta http-equiv="Content-Type" content="text/html; charset=windows-1252">'
    '<title>H</title></head><body><p>A<script>1</script>B \x93q\x94</p><iframe src="x"></iframe><p>C</p></body></html>')
structure_opf = package(manifest='<item id="headless" href="Text/headless.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="legacy" href="Text/legacy.html" media-type="text/html"/>').replace(
    '<itemref idref="chapter"/>', '<itemref idref="chapter"/><itemref idref="headless"/><itemref idref="legacy"/>')
write("render-structure.epub", structure_opf, {
    "OEBPS/Text/chapter one.xhtml": structure_xhtml,
    "OEBPS/Text/headless.xhtml": structure_headless,
    "OEBPS/Text/legacy.html": structure_html.encode("latin-1"),
})
# URL resolution at the container root and backward package versions.
write('path-absolute.epub', package(manifest=nav_item).replace('href="Text/chapter%20one.xhtml"', 'href="/OEBPS/Text/chapter%20one.xhtml"'),
      {'OEBPS/nav.xhtml': NAV.replace('Text/chapter%20one.xhtml#start', '/OEBPS/Text/chapter%20one.xhtml#start')})
write('version-zero.epub', package(version="0"))
write('scheme-relative.epub', package().replace('Text/chapter%20one.xhtml', '//example.invalid/chapter.xhtml'))
write('encoded-traversal.epub', package().replace('Text/chapter%20one.xhtml', '%2e%2e/%2e%2e/outside.xhtml'))
# Manifest fallbacks for foreign and missing spine items and content images.
fallback_manifest = ('<item id="json" href="Text/data.json" media-type="application/json" fallback="json-html"/>'
    '<item id="json-html" href="Text/data.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="plate" href="Text/missing.png" media-type="image/png" fallback="plate-html"/>'
    '<item id="plate-html" href="Text/plate.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="psd" href="Images/art.psd" media-type="image/vnd.adobe.photoshop" fallback="png"/>'
    '<item id="png" href="Images/art.png" media-type="image/png"/>')
fallback_opf = package(manifest=fallback_manifest).replace('<itemref idref="chapter"/>',
    '<itemref idref="json"/><itemref idref="plate" properties="rendition:layout-pre-paginated"/><itemref idref="chapter"/>')
write('fallbacks.epub', fallback_opf, {
    'OEBPS/Text/data.json': '{"text": "not displayed"}',
    'OEBPS/Text/data.xhtml': f'<html xmlns="{XHTML}"><head><title>Data</title></head><body><p id="d">Data fallback text</p></body></html>',
    'OEBPS/Text/plate.xhtml': f'<html xmlns="{XHTML}"><head><title>Plate</title></head><body><p>Plate fallback</p></body></html>',
    'OEBPS/Text/chapter one.xhtml': CHAPTER.replace('</body>', '<img src="../Images/art.psd" alt="Art"/></body>'),
    'OEBPS/Images/art.psd': b'8BPS-not-a-browser-image',
    'OEBPS/Images/art.png': b'\x89PNG\r\n\x1a\n',
})
# Image navigation labels and metadata base direction.
image_nav = (f'<html xmlns="{XHTML}" xmlns:epub="{EPUB}"><head><title>Contents</title></head><body><nav epub:type="toc"><ol>'
    '<li><a href="Text/chapter%20one.xhtml#start"><img src="a.png" alt="Pictured start"/></a></li>'
    '<li><a href="Text/chapter%20one.xhtml" title="Titled link"><img src="a.png" alt=""/></a></li>'
    '</ol></nav></body></html>')
direction_opf = package(manifest=nav_item, metadata='<dc:title id="he" dir="rtl" xml:lang="he">כותרת</dc:title><dc:creator dir="auto">Ada</dc:creator><dc:creator>Root</dc:creator>',
    attrs='dir="ltr"')
write('nav-direction.epub', direction_opf, {'OEBPS/nav.xhtml': image_nav})
# Content URLs resolved at the container root by the renderer.
urls_chapter = (f'<html xmlns="{XHTML}"><head><title>URLs</title></head><body><p>Links</p>'
    '<img id="absolute" src="/media/pic.png" alt="a"/><img id="leaking" src="../../../../media/pic.png" alt="b"/>'
    '<img id="normal" src="../../media/pic.png" alt="c"/><a href="/OEBPS/Text/chapter%20one.xhtml#start">x</a></body></html>')
write('render-urls.epub', package(manifest='<item id="pic" href="../media/pic.png" media-type="image/png"/>'),
      {'OEBPS/Text/chapter one.xhtml': urls_chapter, 'media/pic.png': b'\x89PNG\r\n\x1a\n'})
print(f"Generated {len(list(ROOT.glob('*.epub')))} EPUB fixtures in {ROOT}")
