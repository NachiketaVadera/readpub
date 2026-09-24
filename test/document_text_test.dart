import 'dart:convert';
import 'dart:typed_data';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

const xhtml = 'application/xhtml+xml';

// The paragraph with ID para05 mirrors the structure of the EPUB CFI
// specification's example document: text, an element, then text.
const specLike = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Spec-like</title></head>
<body id="body01">
<h1>Heading</h1>
<p>First</p>
<p>Second</p>
<p>Third</p>
<p id="para05">xxx<em>yyy</em>0123456789</p>
<p>Before <img id="svgimg" src="a.svg" alt="alt text"/> after</p>
</body>
</html>''';

const structured = '''<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head><title> My
  Title </title><style>p { color: red; }</style></head>
<body>
  <h1 id="c1">Chapter
     One</h1>
  <p>Hello <em>big</em>  world<br/>  next line</p>
  <blockquote><p>Quoted</p> tail</blockquote>
  <ul><li>Item <ruby>漢<rt>kan</rt>字<rp>(</rp></ruby></li><li><p>Para in li</p><ol><li>Nested</li></ol></li></ul>
  <pre>
  code  line
</pre>
  <script>var hidden = 1;</script><div hidden="">secret</div>
  <table><tr><td>Cell</td><th>Head</th></tr></table>
  <p role="heading" aria-level="3">Pseudo</p>
  <p lang="fr">Bonjour&nbsp;monde &amp; caf&eacute;<![CDATA[ <ok>]]></p>
  <p>word <a id="pg5"/> next</p>
  <svg xmlns="http://www.w3.org/2000/svg"><title>svg title</title><text>Label</text></svg>
</body>
</html>''';

DocumentText parse(String source, [String type = xhtml]) =>
    DocumentText.parse(source, mediaType: type);

int point(DocumentText document, String expression) =>
    document.resolveCfi(EpubCfi.parse(expression))!.start;

void main() {
  group('text extraction', () {
    final document = parse(structured);

    test('normalizes whitespace and separates blocks', () {
      expect(
        document.text,
        'Chapter One\n'
        'Hello big world\nnext line\n'
        'Quoted\ntail\n'
        'Item 漢字\nPara in li\nNested\n'
        '  code  line\n'
        'Cell\nHead\nPseudo\n'
        'Bonjour monde & café <ok>\n'
        'word next\n'
        'Label',
      );
      expect(document.title, 'My Title');
      expect(document.language, 'en');
    });

    test('describes block roles and context', () {
      final blocks = {for (final block in document.blocks) block.text: block};
      expect(blocks['Chapter One']!.kind, TextBlockKind.heading);
      expect(blocks['Chapter One']!.headingLevel, 1);
      expect(blocks['Hello big world\nnext line']!.kind, TextBlockKind.paragraph);
      expect(blocks['Quoted']!.quoteDepth, 1);
      expect(blocks['tail']!.quoteDepth, 1);
      expect(blocks['Item 漢字']!.kind, TextBlockKind.listItem);
      expect(blocks['Item 漢字']!.listDepth, 1);
      expect(blocks['Para in li']!.kind, TextBlockKind.paragraph);
      expect(blocks['Para in li']!.listDepth, 1);
      expect(blocks['Nested']!.listDepth, 2);
      expect(blocks['  code  line']!.kind, TextBlockKind.preformatted);
      expect(blocks['Cell']!.kind, TextBlockKind.tableCell);
      expect(blocks['Head']!.kind, TextBlockKind.tableCell);
      expect(blocks['Pseudo']!.kind, TextBlockKind.heading);
      expect(blocks['Pseudo']!.headingLevel, 3);
      expect(blocks['Bonjour monde & café <ok>']!.language, 'fr');
      expect(blocks['Label']!.language, 'en');
      for (final block in document.blocks) {
        expect(document.text.substring(block.start, block.end), block.text);
      }
      expect(document.blockAt(0)!.text, 'Chapter One');
      expect(document.blockAt(document.length)!.text, 'Label');
    });

    test('maps IDs, including empty anchors, to following text', () {
      expect(document.offsetOfId('c1'), 0);
      expect(
        document.offsetOfId('pg5'),
        document.text.indexOf('next', document.text.indexOf('word')),
      );
      expect(document.offsetOfId('missing'), isNull);
    });

    test('returns bounded text context without splitting surrogate pairs', () {
      final emoji = parse(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p>a😀bc😀d</p></body></html>',
      );
      final context = emoji.textAround(3, 4, context: 2);
      expect(context.before, '😀');
      expect(context.highlight, 'b');
      expect(context.after, 'c😀');
      expect(emoji.textAround(0, 0).highlight, isNull);
      expect(() => emoji.textAround(3, 99), throwsRangeError);
    });
  });

  group('CFI mapping', () {
    final document = parse(specLike);
    final para = document.text.indexOf('xxx');

    test('resolves the specification example locations', () {
      expect(
        point(document, '/4[body01]/10[para05]/3:10'),
        document.text.indexOf('9') + 1,
      );
      expect(point(document, '/4[body01]/10[para05]/1:0'), para);
      expect(point(document, '/4[body01]/10[para05]/2/1:0'), para + 3);
      expect(point(document, '/4[body01]/10[para05]/2/1:3'), para + 6);
      expect(point(document, '/4/10'), para);
      expect(point(document, '/4/10/2[;s=b]'), para + 3);
      final range = document.resolveCfi(
        EpubCfi.parse('epubcfi(/4[body01]/10[para05],/2/1:1,/3:4)'),
      )!;
      expect(document.text.substring(range.start, range.end), 'yy0123');
      expect(range.match, CfiMatch.exact);
    });

    test('generates CFIs with ID assertions and character offsets', () {
      expect(document.cfiAt(para + 6).toString(), 'epubcfi(/4[body01]/10[para05]/3:0)');
      expect(
        document.cfiAt(para + 6, preferPreceding: true).toString(),
        'epubcfi(/4[body01]/10[para05]/2/1:3)',
      );
      expect(
        document.cfiForRange(para + 4, para + 10).toString(),
        'epubcfi(/4[body01]/10[para05],/2/1:1,/3:4)',
      );
      expect(document.cfiForRange(para, para), document.cfiAt(para));
    });

    test('round-trips every text offset', () {
      for (final source in [specLike, structured]) {
        final text = parse(source);
        for (var offset = 0; offset <= text.length; offset++) {
          // A preceding-biased point after a block or line separator attaches
          // to the end of the previous text; every other offset is exact.
          final preceding = text.cfiAt(offset, preferPreceding: true);
          final back = text.resolveCfi(preceding)!.start;
          if (offset == 0 || text.text[offset - 1] != '\n') {
            expect(back, offset, reason: '$preceding');
          } else {
            expect(back, offset - 1, reason: '$preceding');
          }
          final following = text.resolveCfi(text.cfiAt(offset))!.start;
          if (offset == text.length || text.text[offset] != '\n') {
            expect(following, offset);
          } else {
            expect(following, greaterThan(offset));
          }
        }
      }
    });

    test('supports virtual first and last child positions', () {
      final start = point(document, '/4/10/0');
      final end = point(document, '/4/10/4');
      expect(start, para);
      expect(end, para + 16);
      expect(document.resolveCfi(EpubCfi.parse('/4/10/6')), isNull);
      expect(document.resolveCfi(EpubCfi.parse('/4/10/0/1:0')), isNull);
    });

    test('corrects ID and text assertions or rejects failed assertions', () {
      final moved = document.resolveCfi(EpubCfi.parse('/4[body01]/8[para05]/2/1:3'))!;
      expect(moved.start, para + 6);
      expect(moved.match, CfiMatch.corrected);
      expect(document.resolveCfi(EpubCfi.parse('/4/10[missing]/1:0')), isNull);
      final asserted = document.resolveCfi(EpubCfi.parse('/4/10/2/1:3[yyy,012]'))!;
      expect(asserted.match, CfiMatch.exact);
      final shifted = document.resolveCfi(EpubCfi.parse('/4/10/2/1:1[yyy,012]'))!;
      expect(shifted.start, para + 6);
      expect(shifted.match, CfiMatch.corrected);
      expect(document.resolveCfi(EpubCfi.parse('/4/10/2/1:1[zzz]')), isNull);
    });

    test('clamps excessive offsets and stops at nested indirection', () {
      final clamped = document.resolveCfi(EpubCfi.parse('/4/10/2/1:99'))!;
      expect(clamped.start, para + 6);
      expect(clamped.match, CfiMatch.approximate);
      final image = document.resolveCfi(EpubCfi.parse('/4/12/2[svgimg]!/4/2/1:0'))!;
      expect(image.match, CfiMatch.approximate);
      expect(image.start, document.text.indexOf('after'));
      expect(point(document, '/4/12/2[svgimg]:3'), document.text.indexOf('after'));
    });

    test('collapsed whitespace maps to its source sequence', () {
      final spaced = parse(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p>a \n  b</p></body></html>',
      );
      expect(spaced.text, 'a b');
      expect(spaced.cfiAt(1).toString(), 'epubcfi(/4/2/1:1)');
      expect(spaced.cfiAt(2).toString(), 'epubcfi(/4/2/1:5)');
      expect(point(spaced, '/4/2/1:3'), 2);
    });

    test('uses browser end-of-line handling for character offsets', () {
      final crlf = parse(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p>a\r\nb\rc</p></body></html>',
      );
      expect(crlf.text, 'a b c');
      expect(crlf.cfiAt(4).toString(), 'epubcfi(/4/2/1:4)');
    });

    test('documents without text map to the body', () {
      final empty = parse(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><img src="a.png"/></body></html>',
      );
      expect(empty.text, isEmpty);
      expect(empty.cfiAt(0).toString(), 'epubcfi(/4)');
      expect(empty.resolveCfi(empty.cfiAt(0))!.start, 0);
    });
  });

  group('formats and limits', () {
    test('parses legacy HTML with the HTML5 tree builder', () {
      final html = parse(
        '<!DOCTYPE html><p>One<p>Two <b>bold</b><table><td>cell</table><!-- note -->',
        'text/html',
      );
      expect(html.text, 'One\nTwo bold\ncell');
      // html(root) > body(/4) > p(/2), p(/4), table(/6) > tbody > tr > td.
      expect(html.cfiAt(html.text.indexOf('bold')).toString(), 'epubcfi(/4/4/2/1:0)');
      expect(
        html.cfiAt(html.text.indexOf('cell')).toString(),
        'epubcfi(/4/6/2/2/2/1:0)',
      );
    });

    test('parses SVG content documents', () {
      final svg = parse(
        '<svg xmlns="http://www.w3.org/2000/svg"><desc>no</desc><text>Hi <tspan>there</tspan></text></svg>',
        'image/svg+xml',
      );
      expect(svg.text, 'Hi there');
      expect(svg.cfiAt(0).toString(), 'epubcfi(/4/1:0)');
    });

    test('decodes bytes with byte order marks and legacy charsets', () {
      final withBom = DocumentText.decode(
        Uint8List.fromList([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(
            '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>é</p></body></html>',
          ),
        ]),
        mediaType: xhtml,
      );
      expect(withBom.text, 'é');
      final legacy = DocumentText.decode(
        Uint8List.fromList(
          latin1.encode(
                '<html><head><meta charset="windows-1252"></head><body><p>caf\xe9',
              ) +
              [0x80] +
              latin1.encode('</p></body></html>'),
        ),
        mediaType: 'text/html',
      );
      expect(legacy.text, 'café€');
    });

    test('rejects malformed, unsupported and oversized documents', () {
      for (final (source, type, limits) in [
        ('<html><body>', xhtml, const ContentLimits()),
        ('<!DOCTYPE html [<!ENTITY x "y">]><html/>', xhtml, const ContentLimits()),
        ('<p/>', 'text/plain', const ContentLimits()),
        ('<a><b><c/></b></a>', xhtml, const ContentLimits(maxDepth: 2)),
        ('<a><b/><c/></a>', xhtml, const ContentLimits(maxElements: 2)),
        ('<a>0123456789</a>', xhtml, const ContentLimits(maxBytes: 8)),
        ('<p>x</p>', 'text/html', const ContentLimits(maxDepth: 2)),
      ]) {
        expect(
          () => DocumentText.parse(source, mediaType: type, limits: limits),
          throwsA(isA<ContentException>()),
          reason: source,
        );
      }
      expect(
        () => DocumentText.parse(
          '<a/>',
          mediaType: xhtml,
          limits: const ContentLimits(maxBytes: 0),
        ),
        throwsArgumentError,
      );
    });
  });
}
