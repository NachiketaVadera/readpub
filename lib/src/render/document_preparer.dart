part of 'render_session.dart';

String _readerCss(ReaderSettings settings, {required bool fixedLayout}) {
  final (background, foreground) = switch (settings.theme) {
    ReaderTheme.light => ('#ffffff', '#1c1c1c'),
    ReaderTheme.dark => ('#17191c', '#eeeeee'),
    ReaderTheme.sepia => ('#f4ecd8', '#3b3023'),
  };
  final base =
      '''
:root { color-scheme: ${settings.theme == ReaderTheme.dark ? 'dark' : 'light'};
  background-color: $background !important; color: $foreground !important; }
html { background-color: $background !important; }
img, svg, video { max-width: 100%; }
''';
  if (fixedLayout) {
    return '$base html, body { width: 100vw; height: 100vh; margin: 0; overflow: hidden; }';
  }
  final typography =
      '''
:root { font-size: ${settings.fontScale * 100}% !important; }
body { line-height: ${settings.lineHeight} !important;
  padding: ${settings.margin}px !important; box-sizing: border-box; }
''';
  if (settings.flow == ReaderFlow.scroll) {
    return '$base$typography body { max-width: 44rem; margin-inline: auto !important; }';
  }
  return '''$base$typography
html { width: 100vw; height: 100vh; overflow: hidden; }
body { width: 100vw; height: 100vh; margin: 0 !important;
  column-width: calc(100vw - ${settings.margin * 2}px);
  column-gap: ${settings.margin * 2}px;
  overflow-x: auto; overflow-y: hidden; }
''';
}

String _prepareXhtml(
  Uint8List bytes,
  String path,
  ReaderSettings settings, {
  required String documentHref,
  required bool fixedLayout,
  required int maxElements,
  required int maxDepth,
}) {
  final text = normalizeLineEndings(decodeContent(bytes, path));
  preflightXml(text, path, maxElements: maxElements, maxDepth: maxDepth);
  try {
    final document = XmlDocument.parse(text, entityMapping: contentEntityMapping);
    final root = document.rootElement;
    if (root.name.local != 'html' || root.name.namespaceUri != xhtmlNamespace) {
      throw ContentException('Content document is not XHTML.', path: path);
    }
    for (final element in document.descendants.whereType<XmlElement>().toList()) {
      final name = element.name.local;
      if (_activeElements.contains(name)) {
        // Replace rather than remove: sibling indices and character data
        // chunks must stay identical for EPUB CFI mapping.
        element.replace(
          XmlElement.tag(
            'template',
            namespaceUri: xhtmlNamespace,
            attributes: [
              // Inside SVG or MathML the default namespace would otherwise
              // make the placeholder a foreign element.
              if (element.name.namespaceUri != xhtmlNamespace)
                XmlAttribute(XmlName.parts('xmlns'), xhtmlNamespace),
              XmlAttribute(XmlName.parts('data-readpub-removed'), name),
              if (element.getAttribute('id') case final id?)
                XmlAttribute(XmlName.parts('id'), id),
            ],
            isSelfClosing: false,
          ),
        );
        continue;
      }
      element.attributes.removeWhere((attribute) {
        final name = attribute.name.local.toLowerCase();
        final value = attribute.value.trimLeft().toLowerCase();
        return name.startsWith('on') ||
            ((name == 'href' || name == 'src') && value.startsWith('javascript:'));
      });
      for (final attribute in element.attributes) {
        if (_urlAttributes.contains(attribute.name.local.toLowerCase())) {
          final contained = _containedReference(attribute.value, documentHref);
          if (contained != null) attribute.value = contained;
        }
      }
      if (name == 'meta' &&
          element.getAttribute('http-equiv')?.trim().toLowerCase() == 'refresh') {
        element.removeAttribute('http-equiv');
        element.removeAttribute('content');
      }
    }
    // Append reader styles after existing content; a document without a head
    // receives them at the end of the root rather than a new first element.
    final head = root.childElements
        .where((e) => e.name.local == 'head' && e.name.namespaceUri == xhtmlNamespace)
        .firstOrNull;
    (head ?? root).children.add(
      XmlElement.tag(
        'style',
        namespaceUri: xhtmlNamespace,
        attributes: [XmlAttribute(XmlName.parts('data-readpub'), 'reader')],
        children: [XmlText(_readerCss(settings, fixedLayout: fixedLayout))],
        isSelfClosing: false,
      ),
    );
    return document.toXmlString().replaceFirst(
      RegExp(r'^<\?xml[^>]*\?>\s*'),
      '<?xml version="1.0" encoding="UTF-8"?>\n',
    );
  } on XmlException catch (error) {
    throw ContentException(
      'Malformed XHTML content document.',
      path: path,
      cause: error,
    );
  }
}

String _prepareHtml(
  Uint8List bytes,
  String path,
  ReaderSettings settings, {
  required String documentHref,
  required bool fixedLayout,
  required int maxElements,
  required int maxDepth,
}) {
  final document = html_parser.parse(decodeContent(bytes, path));
  var count = 0;
  void visit(html_dom.Node node, int depth) {
    if (depth > maxDepth || ++count > maxElements) {
      throw ContentException('HTML content document exceeds limits.', path: path);
    }
    for (final child in node.nodes) {
      visit(child, depth + 1);
    }
  }

  visit(document, 0);
  for (final element in document.querySelectorAll(_activeElements.join(', '))) {
    final placeholder = html_dom.Element.tag('template')
      ..attributes['data-readpub-removed'] = element.localName!;
    if (element.attributes['id'] case final id?) placeholder.attributes['id'] = id;
    element.replaceWith(placeholder);
  }
  var charset = false;
  for (final meta in document.querySelectorAll('meta')) {
    final equivalent = meta.attributes['http-equiv']?.trim().toLowerCase();
    if (equivalent == 'refresh') {
      meta.attributes.remove('http-equiv');
      meta.attributes.remove('content');
    } else if (equivalent == 'content-type') {
      meta.attributes['content'] = 'text/html; charset=utf-8';
      charset = true;
    }
    if (meta.attributes.containsKey('charset')) {
      meta.attributes['charset'] = 'utf-8';
      charset = true;
    }
  }
  for (final element in document.querySelectorAll('*')) {
    element.attributes.removeWhere((name, value) {
      final normalizedName = name.toString().toLowerCase();
      final normalizedValue = value.trimLeft().toLowerCase();
      return normalizedName.startsWith('on') ||
          ((normalizedName == 'href' || normalizedName == 'src') &&
              normalizedValue.startsWith('javascript:'));
    });
    for (final entry in element.attributes.entries.toList()) {
      final name = entry.key.toString().toLowerCase().split(':').last;
      if (_urlAttributes.contains(name)) {
        final contained = _containedReference(entry.value, documentHref);
        if (contained != null) element.attributes[entry.key] = contained;
      }
    }
  }
  final head = document.head;
  if (head == null) {
    throw ContentException('HTML parser produced no document head.', path: path);
  }
  // Declarations are rewritten or appended, never inserted before existing
  // elements, so sibling indices match the original document.
  if (!charset) {
    head.append(html_dom.Element.tag('meta')..attributes['charset'] = 'utf-8');
  }
  final style = html_dom.Element.tag('style')..attributes['data-readpub'] = 'reader';
  style.append(html_dom.Text(_readerCss(settings, fixedLayout: fixedLayout)));
  head.append(style);
  return document.outerHtml;
}

/// Attributes whose URL values are resolved relative to the document.
const _urlAttributes = {'href', 'src', 'poster', 'data'};

/// Rewrites a local URL that leaves the container, or starts with `/`, into
/// the document-relative URL that EPUB's container root URL resolves it to.
///
/// A browser resolves such URLs against the loopback origin, outside the
/// session's private path; returns null for URLs that need no rewrite.
String? _containedReference(String value, String documentHref) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
  final Uri target;
  try {
    target = Uri.parse(trimmed);
  } on FormatException {
    return null;
  }
  if (target.hasScheme || target.hasAuthority) return null;
  final probe = _probeRoot.resolve(documentHref).resolveUri(target);
  if (probe.path.startsWith(_probeRoot.path)) return null;
  final resolved = _containerRoot.resolve(documentHref).resolveUri(target);
  final depth = '/'.allMatches(Uri.parse(documentHref).path).length;
  return '${'../' * depth}${resolved.path.substring(1)}'
      '${target.hasQuery ? '?${target.query}' : ''}'
      '${target.hasFragment ? '#${target.fragment}' : ''}';
}

final _containerRoot = Uri.parse('https://container.invalid/');
final _probeRoot = Uri.parse('https://container.invalid/__root__/');

/// Active elements replaced by inert placeholders.
const _activeElements = ['base', 'script', 'iframe', 'object', 'embed'];
