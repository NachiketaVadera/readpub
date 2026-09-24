/// Shared decoding and bounded parsing of publication content documents.
///
/// The renderer and the text model must interpret a document identically so
/// that locations computed from prepared browser content match locations
/// computed from the original resource.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../error/publication_exception.dart';

/// The XHTML namespace.
const xhtmlNamespace = 'http://www.w3.org/1999/xhtml';

/// Named character references accepted in XML content documents.
///
/// EPUB 2 XHTML commonly uses entities declared by XHTML document types, which
/// browsers resolve from built-in tables without fetching a DTD. External and
/// internal DTD declarations are never processed.
const contentEntityMapping = XmlDefaultEntityMapping.html5();

/// Media types a browser displays as a reading-order document.
const displayableContentTypes = {
  'application/xhtml+xml',
  'text/html',
  'image/svg+xml',
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/avif',
};

/// EPUB 3.3 core media types, which reading systems support without
/// fallbacks.
const coreMediaTypes = {
  'image/gif',
  'image/jpeg',
  'image/png',
  'image/svg+xml',
  'image/webp',
  'audio/mpeg',
  'audio/mp4',
  'audio/ogg',
  'audio/opus',
  'text/css',
  'font/ttf',
  'application/font-sfnt',
  'font/otf',
  'application/vnd.ms-opentype',
  'font/woff',
  'application/font-woff',
  'font/woff2',
  'application/xhtml+xml',
  'application/javascript',
  'application/ecmascript',
  'text/javascript',
  'application/x-dtbncx+xml',
  'application/smil+xml',
  'application/pls+xml',
};

/// Validates configured document limits.
void checkContentLimits(int maxBytes, int maxElements, int maxDepth) {
  if (maxBytes <= 0 || maxElements <= 0 || maxDepth <= 0) {
    throw ArgumentError('Content limits must be positive.');
  }
}

/// Applies XML end-of-line handling, as browsers do before parsing.
///
/// Without this step DOM text lengths differ from browser DOM text lengths
/// for documents with CRLF line endings, invalidating character offsets.
String normalizeLineEndings(String text) =>
    text.contains('\r') ? text.replaceAll('\r\n', '\n').replaceAll('\r', '\n') : text;

/// Decodes content document bytes.
///
/// UTF-16 is detected by byte order mark or leading `<`; declared ISO-8859-1
/// and Windows-1252 documents are decoded as Windows-1252; everything else
/// must be valid UTF-8.
String decodeContent(Uint8List bytes, String path) {
  try {
    final utf16Le = bytes.length >= 4 && bytes[0] == 0x3c && bytes[1] == 0;
    final utf16Be = bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 0x3c;
    final hasBom =
        bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff));
    if (hasBom || utf16Le || utf16Be) {
      if (bytes.length.isOdd) throw const FormatException('Odd UTF-16 byte count.');
      final little = utf16Le || (hasBom && bytes[0] == 0xff);
      final data = ByteData.sublistView(bytes);
      return String.fromCharCodes([
        for (var i = hasBom ? 2 : 0; i < bytes.length; i += 2)
          data.getUint16(i, little ? Endian.little : Endian.big),
      ]);
    }
    final probe = latin1.decode(bytes.take(1024).toList(), allowInvalid: true);
    final declared = RegExp(
      r'''(?:encoding|charset)\s*=\s*["']?([a-zA-Z0-9_-]+)''',
      caseSensitive: false,
    ).firstMatch(probe)?.group(1)?.toLowerCase();
    if (declared == 'iso-8859-1' ||
        declared == 'latin1' ||
        declared == 'windows-1252') {
      // Browsers decode ISO-8859-1 labels as Windows-1252.
      return String.fromCharCodes([
        for (final byte in bytes)
          byte >= 0x80 && byte <= 0x9f ? _windows1252[byte - 0x80] : byte,
      ]);
    }
    final text = utf8.decode(bytes);
    return text.startsWith('\ufeff') ? text.substring(1) : text;
  } on FormatException catch (error) {
    throw ContentException('Cannot decode content document.', path: path, cause: error);
  }
}

/// Checks XML well-formedness, DTD subsets and element limits before a DOM
/// is built, so that nested input cannot exhaust the stack.
void preflightXml(
  String text,
  String path, {
  required int maxElements,
  required int maxDepth,
}) {
  try {
    var depth = 0;
    var count = 0;
    for (final event in parseEvents(
      text,
      entityMapping: contentEntityMapping,
      validateNesting: true,
      validateNamespace: true,
      validateDocument: true,
    )) {
      if (event is XmlDoctypeEvent && event.internalSubset != null) {
        throw ContentException(
          'Content document contains an internal DTD subset.',
          path: path,
        );
      }
      if (event is XmlStartElementEvent) {
        if (++count > maxElements || depth + 1 > maxDepth) {
          throw ContentException('Content document exceeds XML limits.', path: path);
        }
        if (!event.isSelfClosing) depth++;
      } else if (event is XmlEndElementEvent) {
        depth--;
      }
    }
  } on XmlException catch (error) {
    throw ContentException('Malformed XML content document.', path: path, cause: error);
  }
}

const _windows1252 = <int>[
  0x20ac, 0x81, 0x201a, 0x192, 0x201e, 0x2026, 0x2020, 0x2021, //
  0x2c6, 0x2030, 0x160, 0x2039, 0x152, 0x8d, 0x17d, 0x8f, //
  0x90, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014, //
  0x2dc, 0x2122, 0x161, 0x203a, 0x153, 0x9d, 0x17e, 0x178, //
];
