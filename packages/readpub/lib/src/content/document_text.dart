import 'dart:math';
import 'dart:typed_data';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../cfi/epub_cfi.dart';
import '../error/publication_exception.dart';
import '../locator/locator.dart';
import 'content_source.dart';

part 'text_builder.dart';

/// Limits applied while decoding and parsing one content document.
final class ContentLimits {
  /// Creates content limits; every value must be positive when used.
  const ContentLimits({
    this.maxBytes = 8 * 1024 * 1024,
    this.maxElements = 100000,
    this.maxDepth = 128,
  });

  /// The maximum encoded document size in bytes.
  final int maxBytes;

  /// The maximum number of elements.
  final int maxElements;

  /// The maximum element nesting depth.
  final int maxDepth;
}

/// The structural role of a [TextBlock], from its nearest block element.
enum TextBlockKind {
  /// A paragraph or another generic text block.
  paragraph,

  /// A heading; see [TextBlock.headingLevel].
  heading,

  /// Inline content directly inside a list item.
  listItem,

  /// Preformatted text, whose whitespace is preserved.
  preformatted,

  /// A table header or data cell.
  tableCell,

  /// A table or figure caption.
  caption,
}

/// How a CFI was matched to document text.
enum CfiMatch {
  /// Every step matched the document structure and all assertions held.
  exact,

  /// ID or text assertions relocated a step or offset that no longer matched.
  corrected,

  /// The target was clamped or ended at an unsupported indirection.
  approximate,
}

/// A text range resolved from a content-document CFI.
final class CfiTextRange {
  /// Creates a resolved range.
  const CfiTextRange(this.start, this.end, this.match);

  /// The start offset in [DocumentText.text].
  final int start;

  /// The end offset in [DocumentText.text]; equal to [start] for a point.
  final int end;

  /// How the CFI was matched.
  final CfiMatch match;
}

/// A block of reading text with its structural context.
final class TextBlock {
  TextBlock._(
    this._document,
    this.start,
    this.end,
    this.kind, {
    required this.headingLevel,
    required this.listDepth,
    required this.quoteDepth,
    required this.language,
  });

  final String _document;

  /// The start offset of this block in [DocumentText.text].
  final int start;

  /// The end offset of this block in [DocumentText.text].
  final int end;

  /// The block role, taken from the nearest enclosing block element.
  final TextBlockKind kind;

  /// The heading rank from 1 to 6, for headings only.
  final int? headingLevel;

  /// The number of enclosing list items.
  final int listDepth;

  /// The number of enclosing block quotations.
  final int quoteDepth;

  /// The inherited language of the block element, if declared.
  final String? language;

  /// The block text.
  String get text => _document.substring(start, end);

  @override
  String toString() => 'TextBlock($kind, $start-$end: $text)';
}

/// Normalized reading text of one XHTML, HTML or SVG content document, mapped
/// to content-document CFIs.
///
/// Text is extracted as a browser would display it without author CSS:
/// whitespace collapses within blocks, `br` becomes a line feed and blocks are
/// separated by one line feed. The document head, scripts, styles, templates,
/// ruby annotations (`rt`, `rp`), embedded content fallbacks, SVG descriptive
/// and definition elements and `hidden` elements are excluded. CSS visibility
/// and generated content are not evaluated. Offsets are UTF-16 code units in
/// [text].
///
/// Every source character is associated with its element path and character
/// data chunk, so text offsets and content-document CFIs can be converted in
/// both directions. CFIs are relative to the document's root element and
/// count elements and character data exactly as a browser DOM does.
final class DocumentText {
  DocumentText._(
    this.mediaType,
    this.text,
    this.blocks,
    this.title,
    this.language,
    this._root,
    this._body,
    this._runs,
    this._ids,
  );

  /// Parses decoded content document [source].
  ///
  /// [mediaType] must be `application/xhtml+xml`, `image/svg+xml` or
  /// `text/html`. XML documents are parsed with HTML named character
  /// references and browser end-of-line handling; internal DTD subsets are
  /// rejected. Throws a [ContentException] for malformed input, unsupported
  /// media types or exceeded [limits].
  factory DocumentText.parse(
    String source, {
    required String mediaType,
    ContentLimits limits = const ContentLimits(),
    String? path,
  }) {
    checkContentLimits(limits.maxBytes, limits.maxElements, limits.maxDepth);
    if (source.length > limits.maxBytes) {
      throw ContentException('Content document exceeds byte limit.', path: path);
    }
    final builder = _TextBuilder(limits, path);
    switch (mediaType) {
      case 'application/xhtml+xml' || 'image/svg+xml':
        _walkXml(normalizeLineEndings(source), builder, path);
      case 'text/html':
        _walkHtml(html_parser.parse(source), builder);
      default:
        throw ContentException(
          'Unsupported content document type $mediaType.',
          path: path,
        );
    }
    return builder.finish(mediaType);
  }

  /// Decodes content document [bytes] and parses them like
  /// [DocumentText.parse].
  ///
  /// UTF-8, UTF-16 and declared ISO-8859-1 or Windows-1252 content is decoded.
  factory DocumentText.decode(
    Uint8List bytes, {
    required String mediaType,
    ContentLimits limits = const ContentLimits(),
    String? path,
  }) {
    checkContentLimits(limits.maxBytes, limits.maxElements, limits.maxDepth);
    if (bytes.length > limits.maxBytes) {
      throw ContentException('Content document exceeds byte limit.', path: path);
    }
    return DocumentText.parse(
      decodeContent(bytes, path ?? ''),
      mediaType: mediaType,
      limits: limits,
      path: path,
    );
  }

  /// The parsed media type.
  final String mediaType;

  /// The normalized reading text.
  final String text;

  /// The text blocks in document order.
  final List<TextBlock> blocks;

  /// The document title, from its first `title` element.
  final String? title;

  /// The language declared on the root element.
  final String? language;

  final _Element _root;
  final _Element? _body;
  final List<_Run> _runs;
  final Map<String, _Element> _ids;

  /// The text length in UTF-16 code units.
  int get length => text.length;

  /// Returns the content-document CFI of the point at text [offset].
  ///
  /// Where [offset] falls between two source text runs, such as between
  /// blocks, the point attaches to the following text unless
  /// [preferPreceding] is true. Element steps carry ID assertions. A document
  /// without text maps every offset to its `body`, or to the root's first
  /// child position.
  EpubCfi cfiAt(int offset, {bool preferPreceding = false}) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    if (_runs.isEmpty) {
      final body = _body;
      return EpubCfi(
        CfiPath(
          body == null ? [CfiStep(_root.elements.isEmpty ? 0 : 2)] : _stepsTo(body),
        ),
      );
    }
    _Run run;
    if (preferPreceding) {
      // The last run starting before the offset.
      var low = 0;
      var high = _runs.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (_runs[middle].textStart < offset) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      run = _runs[max(0, low - 1)];
    } else {
      // The first run ending after the offset.
      var low = 0;
      var high = _runs.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (_runs[middle].textEnd <= offset) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      run = _runs[min(_runs.length - 1, low)];
    }
    final delta = offset.clamp(run.textStart, run.textEnd) - run.textStart;
    final source = run.linear
        ? run.sourceStart + delta
        : run.sourceStart + (delta == 0 ? 0 : run.sourceLength);
    return EpubCfi(
      CfiPath([
        ..._stepsTo(run.chunk.parent),
        CfiStep(run.chunk.index),
      ], offset: CfiCharacterOffset(source)),
    );
  }

  /// Returns the content-document CFI range from [start] to [end].
  ///
  /// An empty range returns a point.
  EpubCfi cfiForRange(int start, int end) {
    RangeError.checkValidRange(start, end, length);
    final first = cfiAt(start);
    if (start == end) return first;
    final last = cfiAt(end, preferPreceding: true);
    return last.compareTo(first) <= 0 ? first : EpubCfi.between(first, last);
  }

  /// Resolves a content-document CFI to a text range.
  ///
  /// Steps are relative to the document root element, as produced by
  /// [cfiAt]. Failed ID assertions are corrected by locating the ID, and
  /// failed text assertions by locating the asserted text nearest to the
  /// original point. Returns null when the path cannot be followed or an
  /// assertion cannot be corrected, as EPUB CFI requires.
  CfiTextRange? resolveCfi(EpubCfi cfi) {
    final start = _resolve(cfi.startPath);
    if (start == null) return null;
    if (!cfi.isRange) return CfiTextRange(start.$1, start.$1, start.$2);
    final end = _resolve(cfi.endPath);
    if (end == null) return null;
    final match = CfiMatch.values[max(start.$2.index, end.$2.index)];
    return CfiTextRange(start.$1, max(start.$1, end.$1), match);
  }

  /// Returns the text offset at which the element with [id] starts.
  ///
  /// Empty elements, such as page-break anchors, map to the following text.
  int? offsetOfId(String id) => _ids[id]?.textStart;

  /// Returns the block containing [offset], or the block following it.
  TextBlock? blockAt(int offset) {
    for (final block in blocks) {
      if (offset < block.end || (offset == block.end && block == blocks.last)) {
        return block;
      }
    }
    return null;
  }

  /// Returns text context around the range from [start] to [end].
  ///
  /// Context is limited to [context] code units on each side and never splits
  /// a surrogate pair. An empty range yields no highlight.
  LocatorText textAround(int start, int end, {int context = 40}) {
    RangeError.checkValidRange(start, end, length);
    RangeError.checkNotNegative(context, 'context');
    var before = max(0, start - context);
    if (before > 0 && _isLowSurrogate(text.codeUnitAt(before))) before--;
    var after = min(length, end + context);
    if (after < length && _isLowSurrogate(text.codeUnitAt(after))) after++;
    String? slice(int from, int to) => from < to ? text.substring(from, to) : null;
    return LocatorText(
      before: slice(before, start),
      highlight: slice(start, end),
      after: slice(end, after),
    );
  }

  List<CfiStep> _stepsTo(_Element element) {
    final steps = <CfiStep>[];
    for (var node = element; node.parent != null; node = node.parent!) {
      steps.add(CfiStep(node.index, id: node.id));
    }
    return steps.reversed.toList();
  }

  (int, CfiMatch)? _resolve(CfiPath path) {
    var element = _root;
    var match = CfiMatch.exact;
    final steps = path.steps;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step.indirect) return (element.textStart, CfiMatch.approximate);
      if (step.index.isOdd) {
        final index = (step.index - 1) >> 1;
        if (index >= element.chunks.length) return null;
        return _resolveChunk(element.chunks[index], path.offset, match);
      }
      final count = element.elements.length;
      if (step.index == 0 || step.index == 2 * (count + 1)) {
        if (i != steps.length - 1) return null;
        return (step.index == 0 ? element.textStart : element.textEnd, match);
      }
      final ordinal = step.index >> 1;
      var child = ordinal <= count ? element.elements[ordinal - 1] : null;
      final id = step.id;
      if (id != null && child?.id != id) {
        child = _ids[id];
        if (child == null) return null;
        match = CfiMatch.corrected;
      }
      if (child == null) return null;
      element = child;
    }
    if (path.offset case CfiOffset(indirect: true)) {
      return (element.textStart, CfiMatch.approximate);
    }
    return (element.textStart, match);
  }

  (int, CfiMatch)? _resolveChunk(_Chunk chunk, CfiOffset? offset, CfiMatch match) {
    if (offset is! CfiCharacterOffset) return (chunk.toText(0), match);
    if (offset.indirect) return (chunk.toText(0), CfiMatch.approximate);
    var position = offset.offset;
    var result = match;
    if (position > chunk.length) {
      position = chunk.length;
      result = CfiMatch.approximate;
    }
    var point = chunk.toText(position);
    final before = offset.textBefore == null ? null : _collapse(offset.textBefore!);
    final after = offset.textAfter == null ? null : _collapse(offset.textAfter!);
    if (before == null && after == null) return (point, result);
    if (_contextMatches(point, before, after)) return (point, result);
    final corrected = _locateContext(point, before ?? '', after ?? '');
    if (corrected == null) return null;
    point = corrected;
    return (point, result == CfiMatch.exact ? CfiMatch.corrected : result);
  }

  bool _contextMatches(int point, String? before, String? after) {
    if (before != null && _collapsedBefore(point, before.length) != before) {
      return false;
    }
    return after == null || _collapsedAfter(point, after.length) == after;
  }

  int? _locateContext(int point, String before, String after) {
    final needle = '$before$after';
    if (needle.trim().isEmpty) return null;
    final haystack = _searchable;
    int? best;
    var scanned = 0;
    for (
      var index = haystack.indexOf(needle);
      index >= 0 && scanned < 10000;
      index = haystack.indexOf(needle, index + 1), scanned++
    ) {
      final candidate = index + before.length;
      if (best == null || (candidate - point).abs() < (best - point).abs()) {
        best = candidate;
      }
    }
    return best;
  }

  late final String _searchable = text.replaceAll('\n', ' ');

  String _collapsedBefore(int point, int count) {
    final units = <int>[];
    for (var i = point - 1; i >= 0 && units.length < count; i--) {
      final unit = text.codeUnitAt(i);
      if (!_isSpace(unit)) {
        units.add(unit);
      } else if (units.isEmpty || units.last != 0x20) {
        units.add(0x20);
      }
    }
    return String.fromCharCodes(units.reversed);
  }

  String _collapsedAfter(int point, int count) {
    final units = <int>[];
    for (var i = point; i < length && units.length < count; i++) {
      final unit = text.codeUnitAt(i);
      if (!_isSpace(unit)) {
        units.add(unit);
      } else if (units.isEmpty || units.last != 0x20) {
        units.add(0x20);
      }
    }
    return String.fromCharCodes(units);
  }
}

String _collapse(String value) => value.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d || unit == 0x0c;

bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
