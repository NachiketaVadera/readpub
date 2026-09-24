part of 'epub_publication.dart';

String _decodeXml(Uint8List bytes, String path) {
  try {
    final hasBom =
        bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff));
    final le = bytes.length >= 4 && bytes[0] == 0x3c && bytes[1] == 0 && bytes[3] == 0;
    final be = bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 0x3c && bytes[2] == 0;
    final String text;
    if (hasBom || le || be) {
      if (bytes.length.isOdd) {
        throw const FormatException('Truncated UTF-16 code unit.');
      }
      final littleEndian = le || (hasBom && bytes[0] == 0xff);
      final data = ByteData.sublistView(bytes);
      text = String.fromCharCodes([
        for (var i = hasBom ? 2 : 0; i < bytes.length; i += 2)
          data.getUint16(i, littleEndian ? Endian.little : Endian.big),
      ]);
    } else {
      text = utf8.decode(bytes);
    }
    final declaration = RegExp(
      r'^<\?xml\s+[^?]*encoding\s*=\s*["\x27]([^"\x27]+)',
      caseSensitive: false,
    ).firstMatch(text);
    final encoding = declaration?.group(1)?.toLowerCase();
    if (encoding != null &&
        !{'utf-8', 'utf-16', 'utf-16le', 'utf-16be'}.contains(encoding)) {
      throw FormatException('Unsupported EPUB XML encoding: $encoding.');
    }
    for (final rune in text.runes) {
      if (!(rune == 9 ||
          rune == 10 ||
          rune == 13 ||
          (rune >= 0x20 && rune <= 0xd7ff) ||
          (rune >= 0xe000 && rune <= 0xfffd) ||
          (rune >= 0x10000 && rune <= 0x10ffff))) {
        throw const FormatException('Invalid XML character.');
      }
    }
    return text;
  } on FormatException catch (error) {
    throw EpubException('Invalid EPUB XML encoding.', path: path, cause: error);
  }
}

XmlDocument _boundedXml(String text, String path, EpubParserOptions options) {
  try {
    var depth = 0;
    var elements = 0;
    // Pull events before constructing a DOM: nested input cannot exhaust the
    // stack before the configured limits have been checked.
    for (final event in parseEvents(
      text,
      validateNesting: true,
      validateNamespace: true,
      validateDocument: true,
    )) {
      if (event is XmlDoctypeEvent && event.internalSubset != null) {
        throw EpubSecurityException(
          'XML internal DTD subsets are forbidden.',
          path: path,
        );
      }
      if (event is XmlStartElementEvent) {
        if (++elements > options.maxXmlElements || depth + 1 > options.maxXmlDepth) {
          throw EpubLimitException(
            'XML depth or element count exceeds limit.',
            path: path,
          );
        }
        if (!event.isSelfClosing) depth++;
      } else if (event is XmlEndElementEvent) {
        depth--;
      }
    }
    // package:xml never retrieves external DTDs. Historical NCX doctypes are
    // therefore accepted without network access or external entity expansion.
    return XmlDocument.parse(text);
  } on XmlException catch (error) {
    throw EpubException('Malformed EPUB XML.', path: path, cause: error);
  }
}

const _opfNs = 'http://www.idpf.org/2007/opf';
const _dcNs = 'http://purl.org/dc/elements/1.1/';
const _xhtmlNs = 'http://www.w3.org/1999/xhtml';
const _epubNs = 'http://www.idpf.org/2007/ops';
const _ncxNs = 'http://www.daisy.org/z3986/2005/ncx/';
const _xmlNs = 'http://www.w3.org/XML/1998/namespace';
const _encNs = 'http://www.w3.org/2001/04/xmlenc#';
const _containerNs = 'urn:oasis:names:tc:opendocument:xmlns:container';
bool _matches(XmlElement element, String local, String namespace) =>
    element.name.local == local && element.name.namespaceUri == namespace;
String? _attribute(XmlElement element, String name) => name == 'lang'
    ? element.getAttribute(name, namespaceUri: _xmlNs)
    : element.getAttribute(name);
String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

extension on Iterable<XmlElement> {
  XmlElement? firstWhereOrNull(bool Function(XmlElement) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
