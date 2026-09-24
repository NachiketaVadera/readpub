part of 'document_text.dart';

const _svgNamespace = 'http://www.w3.org/2000/svg';
const _mathNamespace = 'http://www.w3.org/1998/Math/MathML';

/// An element in the CFI structure of a document.
final class _Element {
  _Element(this.parent, this.index, this.id);

  final _Element? parent;

  /// The even CFI index within [parent].
  final int index;
  final String? id;
  final List<_Element> elements = [];
  final List<_Chunk> chunks = [];
  int textStart = -1;
  int textEnd = -1;
  bool closed = false;
}

/// A possibly-empty chunk of character data between sibling elements.
final class _Chunk {
  _Chunk(this.parent, this.index);

  final _Element parent;

  /// The odd CFI index within [parent].
  final int index;

  /// The chunk length in UTF-16 code units.
  int length = 0;

  /// The text offset used when no source character of the chunk is emitted.
  int anchor = -1;

  /// Mappings for every emitted, collapsed or dropped source character.
  final List<_Run> runs = [];

  int toText(int offset) {
    if (runs.isEmpty) return anchor;
    for (final run in runs) {
      if (offset < run.sourceStart) return run.textStart;
      if (offset < run.sourceStart + run.sourceLength) {
        if (run.linear) return run.textStart + offset - run.sourceStart;
        return offset == run.sourceStart ? run.textStart : run.textEnd;
      }
    }
    return runs.last.textEnd;
  }
}

/// Source characters of a chunk and the text they produce.
///
/// A linear run maps characters one to one. Otherwise it is a collapsed
/// whitespace sequence producing one space, or dropped whitespace producing
/// no text.
final class _Run {
  _Run(
    this.chunk,
    this.sourceStart,
    this.sourceLength,
    this.textStart,
    this.textLength,
  );

  final _Chunk chunk;
  final int sourceStart;
  int sourceLength;
  final int textStart;
  int textLength;

  int get textEnd => textStart + textLength;
  bool get linear => sourceLength == textLength;
}

/// Element state while the builder is inside it.
final class _Open {
  _Open(
    this.node, {
    required this.excluded,
    required this.block,
    required this.kind,
    required this.headingLevel,
    required this.language,
    required this.listItem,
    required this.quote,
    required this.preformatted,
    required this.title,
  });

  final _Element node;
  final bool excluded;
  final bool block;
  final TextBlockKind kind;
  final int? headingLevel;
  final String? language;
  final bool listItem;
  final bool quote;
  final bool preformatted;
  final bool title;
}

/// Attributes that affect text extraction.
typedef _Attributes = ({
  String? id,
  String? language,
  bool hidden,
  String? role,
  String? ariaLevel,
  String? display,
});

/// Builds reading text and its CFI mapping from document events.
final class _TextBuilder {
  _TextBuilder(this.limits, this.path);

  final ContentLimits limits;
  final String? path;
  final StringBuffer _text = StringBuffer();
  final List<TextBlock> _blocks = [];
  final List<_Run> _runs = [];
  final Map<String, _Element> _ids = {};
  final List<_Open> _stack = [];
  final List<_Element> _pendingElements = [];
  final List<_Chunk> _pendingChunks = [];
  _Element? _root;
  _Element? _body;
  String? _rootLanguage;
  int _elements = 0;
  int _preformatted = 0;

  // The open block and whitespace awaiting following content.
  bool _blockOpen = false;
  int _blockStart = 0;
  _Open? _blockElement;
  int _listDepth = 0;
  int _quoteDepth = 0;
  _Run? _space;
  final List<(_Chunk, int, String)> _preformattedSpace = [];
  int _breaks = 0;

  StringBuffer? _titleText;
  String? _title;
  String _document = '';

  int get _length => _text.length;

  void start(String? namespace, String local, _Attributes attributes) {
    if (_stack.length + 1 > limits.maxDepth || ++_elements > limits.maxElements) {
      throw ContentException('Content document exceeds element limits.', path: path);
    }
    final parent = _stack.isEmpty ? null : _stack.last;
    final id = attributes.id == null || attributes.id!.isEmpty ? null : attributes.id;
    final _Element node;
    if (parent == null) {
      if (_root != null) {
        throw ContentException('Content document has several roots.', path: path);
      }
      node = _Element(null, 0, id);
      _root = node;
      _rootLanguage = attributes.language;
    } else {
      node = _Element(parent.node, 2 * (parent.node.elements.length + 1), id);
      parent.node.elements.add(node);
    }
    if (id != null) _ids.putIfAbsent(id, () => node);
    if (namespace == xhtmlNamespace && local == 'body' && parent?.node == _root) {
      _body ??= node;
    }
    _newChunk(node, 1);
    _pendingElements.add(node);

    final xhtml = namespace == xhtmlNamespace;
    final excluded =
        (parent?.excluded ?? false) ||
        (xhtml && attributes.hidden) ||
        _excluded(namespace, local);
    final heading = xhtml ? _headingLevel(local, attributes) : null;
    final block = !excluded && _isBlock(namespace, local, attributes, heading);
    final preformatted = xhtml && _preformattedElements.contains(local);
    final open = _Open(
      node,
      excluded: excluded,
      block: block,
      kind: switch (local) {
        _ when heading != null => TextBlockKind.heading,
        'li' when xhtml => TextBlockKind.listItem,
        _ when preformatted => TextBlockKind.preformatted,
        'td' || 'th' when xhtml => TextBlockKind.tableCell,
        'caption' || 'figcaption' when xhtml => TextBlockKind.caption,
        _ => TextBlockKind.paragraph,
      },
      headingLevel: heading,
      language: attributes.language ?? parent?.language,
      listItem: xhtml && local == 'li',
      quote: xhtml && local == 'blockquote',
      preformatted: preformatted,
      title:
          _title == null &&
          _titleText == null &&
          local == 'title' &&
          (xhtml || namespace == _svgNamespace),
    );
    if (block) _flush();
    _stack.add(open);
    if (open.title) _titleText = StringBuffer();
    if (preformatted && !excluded) _preformatted++;
    if (!excluded && xhtml && local == 'br') _lineBreak();
  }

  void end() {
    final open = _stack.removeLast();
    final node = open.node;
    node.closed = true;
    node.textEnd = node.textStart < 0 ? -1 : _length;
    if (open.block) _flush();
    if (open.preformatted && !open.excluded) _preformatted--;
    if (open.title) {
      _title = _collapse(_titleText.toString()).trim();
      _titleText = null;
    }
    if (node.parent case final parent?) _newChunk(parent, node.index + 1);
  }

  void text(String data) {
    if (_stack.isEmpty || data.isEmpty) return;
    final open = _stack.last;
    final chunk = open.node.chunks.last;
    final base = chunk.length;
    chunk.length += data.length;
    _titleText?.write(data);
    if (open.excluded) return;
    if (_preformatted > 0) {
      _emitPreformatted(data, chunk, base);
    } else {
      _emitCollapsed(data, chunk, base);
    }
  }

  DocumentText finish(String mediaType) {
    final root = _root;
    if (root == null) {
      throw ContentException('Content document has no root element.', path: path);
    }
    _flush();
    _resolvePending();
    _document = _text.toString();
    return DocumentText._(
      mediaType,
      _document,
      List.unmodifiable([
        for (final block in _blocks)
          TextBlock._(
            _document,
            block.start,
            block.end,
            block.kind,
            headingLevel: block.headingLevel,
            listDepth: block.listDepth,
            quoteDepth: block.quoteDepth,
            language: block.language,
          ),
      ]),
      _title == null || _title!.isEmpty ? null : _title,
      _rootLanguage,
      root,
      _body,
      _runs,
      _ids,
    );
  }

  void _newChunk(_Element parent, int index) {
    final chunk = _Chunk(parent, index);
    parent.chunks.add(chunk);
    _pendingChunks.add(chunk);
  }

  void _emitCollapsed(String data, _Chunk chunk, int base) {
    var i = 0;
    while (i < data.length) {
      final space = _isSpace(data.codeUnitAt(i));
      var j = i + 1;
      while (j < data.length && _isSpace(data.codeUnitAt(j)) == space) {
        j++;
      }
      if (!space) {
        _beginContent();
        _addRun(chunk, base + i, j - i, j - i);
        _text.write(data.substring(i, j));
      } else if (_blockOpen && _breaks == 0 && _space == null) {
        // Held until content follows in the same block.
        _space = _Run(chunk, base + i, j - i, -1, 1);
      } else {
        _drop(chunk, base + i, j - i);
      }
      i = j;
    }
  }

  void _emitPreformatted(String data, _Chunk chunk, int base) {
    var i = 0;
    while (i < data.length) {
      final space = _isSpace(data.codeUnitAt(i));
      var j = i + 1;
      while (j < data.length && _isSpace(data.codeUnitAt(j)) == space) {
        j++;
      }
      if (space) {
        var start = i;
        if (!_blockOpen && _preformattedSpace.isEmpty) {
          // Leading line feeds of a block are not reading text.
          final feed = data.lastIndexOf('\n', j - 1);
          if (feed >= i) {
            _drop(chunk, base + i, feed + 1 - i);
            start = feed + 1;
          }
        }
        if (start < j) {
          _preformattedSpace.add((chunk, base + start, data.substring(start, j)));
        }
      } else {
        _beginContent();
        _addRun(chunk, base + i, j - i, j - i);
        _text.write(data.substring(i, j));
      }
      i = j;
    }
  }

  void _beginContent() {
    if (!_blockOpen) {
      if (_length > 0) _text.write('\n');
      _blockOpen = true;
      _blockStart = _length;
      _blockElement = null;
      _listDepth = 0;
      _quoteDepth = 0;
      for (final open in _stack.reversed) {
        if (open.block) _blockElement ??= open;
        if (open.listItem) _listDepth++;
        if (open.quote) _quoteDepth++;
      }
      _space = null;
      _breaks = 0;
    } else if (_breaks > 0) {
      _dropSpace();
      _text.write('\n' * _breaks);
      _breaks = 0;
    }
    if (_space case final space?) {
      _addRun(space.chunk, space.sourceStart, space.sourceLength, 1);
      _text.write(' ');
      _space = null;
    }
    for (final (chunk, start, value) in _preformattedSpace) {
      _addRun(chunk, start, value.length, value.length);
      _text.write(value);
    }
    _preformattedSpace.clear();
    _resolvePending();
  }

  void _lineBreak() {
    if (!_blockOpen) return;
    _dropSpace();
    _breaks++;
  }

  void _flush() {
    _dropSpace();
    _breaks = 0;
    if (!_blockOpen) return;
    final element = _blockElement;
    _blocks.add(
      TextBlock._(
        '',
        _blockStart,
        _length,
        element?.kind ?? TextBlockKind.paragraph,
        headingLevel: element?.headingLevel,
        listDepth: _listDepth,
        quoteDepth: _quoteDepth,
        language: element?.language,
      ),
    );
    _blockOpen = false;
  }

  void _dropSpace() {
    if (_space case final space?) {
      _drop(space.chunk, space.sourceStart, space.sourceLength);
      _space = null;
    }
    for (final (chunk, start, value) in _preformattedSpace) {
      _drop(chunk, start, value.length);
    }
    _preformattedSpace.clear();
  }

  void _drop(_Chunk chunk, int start, int length) =>
      chunk.runs.add(_Run(chunk, start, length, _length, 0));

  void _addRun(_Chunk chunk, int start, int sourceLength, int textLength) {
    final previous = chunk.runs.isEmpty ? null : chunk.runs.last;
    if (previous != null &&
        previous.linear &&
        previous.textLength > 0 &&
        sourceLength == textLength &&
        previous.sourceStart + previous.sourceLength == start &&
        previous.textEnd == _length) {
      previous.sourceLength += sourceLength;
      previous.textLength += textLength;
      return;
    }
    final run = _Run(chunk, start, sourceLength, _length, textLength);
    chunk.runs.add(run);
    _runs.add(run);
  }

  void _resolvePending() {
    for (final element in _pendingElements) {
      element.textStart = _length;
      // An element closed before content resolves to an empty range.
      if (element.closed) element.textEnd = _length;
    }
    _pendingElements.clear();
    for (final chunk in _pendingChunks) {
      chunk.anchor = _length;
    }
    _pendingChunks.clear();
  }
}

void _walkXml(String source, _TextBuilder builder, String? path) {
  try {
    for (final event in parseEvents(
      source,
      entityMapping: contentEntityMapping,
      validateNesting: true,
      validateNamespace: true,
      validateDocument: true,
      withNamespace: true,
      withParent: true,
    )) {
      switch (event) {
        case XmlDoctypeEvent(internalSubset: _?):
          throw ContentException(
            'Content document contains an internal DTD subset.',
            path: path,
          );
        case XmlStartElementEvent():
          String? attribute(String qualifiedName) {
            for (final item in event.attributes) {
              if (item.name == qualifiedName) return item.value;
            }
            return null;
          }
          builder.start(event.namespaceUri, event.localName, (
            id: attribute('id'),
            language: attribute('xml:lang') ?? attribute('lang'),
            hidden: attribute('hidden') != null,
            role: attribute('role'),
            ariaLevel: attribute('aria-level'),
            display: attribute('display'),
          ));
          if (event.isSelfClosing) builder.end();
        case XmlEndElementEvent():
          builder.end();
        case XmlTextEvent():
          builder.text(event.value);
        case XmlCDATAEvent():
          builder.text(event.value);
        default:
          break;
      }
    }
  } on XmlException catch (error) {
    throw ContentException('Malformed XML content document.', path: path, cause: error);
  }
}

void _walkHtml(html_dom.Node node, _TextBuilder builder) {
  for (final child in node.nodes) {
    if (child is html_dom.Element) {
      final attributes = child.attributes;
      builder.start(child.namespaceUri, child.localName ?? '', (
        id: attributes['id'],
        language: attributes['xml:lang'] ?? attributes['lang'],
        hidden: attributes.containsKey('hidden'),
        role: attributes['role'],
        ariaLevel: attributes['aria-level'],
        display: attributes['display'],
      ));
      _walkHtml(child, builder);
      builder.end();
    } else if (child is html_dom.Text) {
      builder.text(child.data);
    }
  }
}

const _preformattedElements = {'pre', 'listing', 'xmp', 'plaintext'};

const _blockElements = {
  'address', 'article', 'aside', 'blockquote', 'body', 'caption', 'center', //
  'dd', 'details', 'dialog', 'dir', 'div', 'dl', 'dt', 'fieldset', //
  'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', //
  'h6', 'header', 'hgroup', 'hr', 'html', 'legend', 'li', 'listing', 'main', //
  'menu', 'nav', 'ol', 'p', 'plaintext', 'pre', 'section', 'summary', //
  'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul', 'xmp', //
};

const _excludedXhtml = {
  'audio', 'canvas', 'datalist', 'embed', 'head', 'iframe', 'noembed', //
  'noframes', 'object', 'rp', 'rt', 'rtc', 'script', 'select', 'style', //
  'template', 'textarea', 'title', 'video', //
};

const _excludedSvg = {
  'clipPath', 'defs', 'desc', 'filter', 'linearGradient', 'marker', 'mask', //
  'metadata', 'pattern', 'radialGradient', 'script', 'style', 'symbol', //
  'title', //
};

bool _excluded(String? namespace, String local) => switch (namespace) {
  xhtmlNamespace => _excludedXhtml.contains(local),
  _svgNamespace => _excludedSvg.contains(local),
  _mathNamespace => local == 'annotation' || local == 'annotation-xml',
  _ => false,
};

bool _isBlock(String? namespace, String local, _Attributes attributes, int? heading) =>
    switch (namespace) {
      xhtmlNamespace => heading != null || _blockElements.contains(local),
      _svgNamespace => local == 'svg' || local == 'text',
      _mathNamespace => local == 'math' && attributes.display == 'block',
      _ => false,
    };

int? _headingLevel(String local, _Attributes attributes) {
  if (RegExp(r'^h[1-6]$').hasMatch(local)) return int.parse(local.substring(1));
  if (attributes.role?.split(RegExp(r'\s+')).contains('heading') != true ||
      !_blockElements.contains(local)) {
    return null;
  }
  final level = int.tryParse(attributes.ariaLevel?.trim() ?? '');
  return level != null && level >= 1 && level <= 6 ? level : 2;
}
