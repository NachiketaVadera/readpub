part of 'epub_publication.dart';

final class _NavigationResult {
  const _NavigationResult(
    this.toc,
    this.landmarks,
    this.pages, [
    this.collections = const [],
  ]);
  final List<Link> toc;
  final List<Link> landmarks;
  final List<Link> pages;
  final List<PublicationCollection> collections;
}

final class _NavigationBudget {
  _NavigationBudget(this.options, this.path);
  final EpubParserOptions options;
  final String path;
  int count = 0;

  void visit(int depth) {
    if (++count > options.maxNavigationItems || depth > options.maxNavigationDepth) {
      throw EpubLimitException(
        'Navigation exceeds its depth or item limit.',
        path: path,
      );
    }
  }
}

final class _NavReader {
  const _NavReader(this.parser, this.path, this.opfPath);
  final _EpubParser parser;
  final String path;
  final String opfPath;

  Future<_NavigationResult> read() async {
    final document = await parser._xml(path);
    if (!_matches(document.rootElement, 'html', _xhtmlNs)) {
      throw EpubException('Navigation document has no XHTML root.', path: path);
    }
    final budget = _NavigationBudget(parser.options, path);
    final byRole = <String, List<Link>>{};
    for (final nav in document.descendants.whereType<XmlElement>().where(
      (element) => _matches(element, 'nav', _xhtmlNs),
    )) {
      final roles = _tokens(nav.getAttribute('type', namespaceUri: _epubNs));
      if (roles.isEmpty) continue;
      final list = nav.childElements.firstWhereOrNull(
        (e) => _matches(e, 'ol', _xhtmlNs),
      );
      if (list == null) continue;
      final links = _list(list, budget, 1);
      for (final role in roles) {
        byRole.putIfAbsent(role, () => links);
      }
    }
    return _NavigationResult(
      byRole['toc'] ?? const [],
      byRole['landmarks'] ?? const [],
      byRole['page-list'] ?? const [],
      [
        for (final entry in byRole.entries)
          if (!{'toc', 'landmarks', 'page-list'}.contains(entry.key))
            PublicationCollection(role: entry.key, links: entry.value),
      ],
    );
  }

  List<Link> _list(XmlElement list, _NavigationBudget budget, int depth) {
    final result = <Link>[];
    for (final li in list.childElements.where((e) => _matches(e, 'li', _xhtmlNs))) {
      budget.visit(depth);
      final label = li.childElements.firstWhereOrNull(
        (e) => _matches(e, 'a', _xhtmlNs) || _matches(e, 'span', _xhtmlNs),
      );
      final nested = li.childElements.firstWhereOrNull(
        (e) => _matches(e, 'ol', _xhtmlNs),
      );
      final children = nested == null
          ? const <Link>[]
          : _list(nested, budget, depth + 1);
      if (label == null) continue;
      final title = _labelText(label);
      final reference = _matches(label, 'a', _xhtmlNs)
          ? label.getAttribute('href')
          : null;
      if (title.isEmpty || (reference == null && children.isEmpty)) continue;
      result.add(
        Link(
          href: reference == null
              ? ''
              : _resolveHref(
                  reference,
                  path,
                  element: label,
                  warnings: parser.warnings,
                ),
          title: title,
          rels: _tokens(label.getAttribute('type', namespaceUri: _epubNs)),
          children: children,
        ),
      );
    }
    return result;
  }
}

final class _NcxReader {
  const _NcxReader(this.parser, this.path, this.opfPath);
  final _EpubParser parser;
  final String path;
  final String opfPath;

  Future<_NavigationResult> read() async {
    final document = await parser._xml(path);
    final root = document.rootElement;
    if (!_matches(root, 'ncx', _ncxNs)) {
      throw EpubException('Navigation document has no NCX root.', path: path);
    }
    final budget = _NavigationBudget(parser.options, path);
    final map = _child(root, 'navMap');
    final pages = _child(root, 'pageList');
    return _NavigationResult(
      map == null ? const [] : _nodes(map, 'navPoint', budget, 1),
      const [],
      pages == null ? const [] : _nodes(pages, 'pageTarget', budget, 1),
      [
        for (final list in root.childElements.where(
          (e) => _matches(e, 'navList', _ncxNs),
        ))
          PublicationCollection(
            role: 'ncx:${list.getAttribute('id') ?? 'nav-list'}',
            links: _nodes(list, 'navTarget', budget, 1),
          ),
      ],
    );
  }

  XmlElement? _child(XmlElement parent, String local) =>
      parent.childElements.firstWhereOrNull((e) => _matches(e, local, _ncxNs));

  List<Link> _nodes(
    XmlElement parent,
    String kind,
    _NavigationBudget budget,
    int depth,
  ) {
    final result = <Link>[];
    for (final node in parent.childElements.where((e) => _matches(e, kind, _ncxNs))) {
      budget.visit(depth);
      final content = _child(node, 'content');
      final label = _child(node, 'navLabel');
      final text = label == null ? null : _child(label, 'text');
      final title = text == null ? '' : _clean(text.innerText);
      final reference = content?.getAttribute('src');
      final children = kind == 'navPoint'
          ? _nodes(node, kind, budget, depth + 1)
          : const <Link>[];
      if (title.isEmpty || (reference == null && children.isEmpty)) continue;
      result.add(
        Link(
          href: reference == null
              ? ''
              : _resolveHref(
                  reference,
                  path,
                  element: content,
                  warnings: parser.warnings,
                ),
          title: title,
          properties: {
            'value': ?node.getAttribute('value'),
            'type': ?node.getAttribute('type'),
          },
          children: children,
        ),
      );
    }
    return result;
  }
}

/// The text of a navigation label, using `img` alternative text for embedded
/// images and the label's `title` attribute when it has no text, as EPUB 3.3
/// navigation documents require for image-only labels.
String _labelText(XmlElement label) {
  final buffer = StringBuffer();
  void visit(XmlNode node) {
    for (final child in node.children) {
      if (child is XmlText || child is XmlCDATA) {
        buffer.write(child.value);
      } else if (child is XmlElement) {
        if (_matches(child, 'img', _xhtmlNs)) {
          buffer.write(' ${child.getAttribute('alt') ?? ''} ');
        } else {
          visit(child);
        }
      }
    }
  }

  visit(label);
  final text = _clean(buffer.toString());
  return text.isNotEmpty ? text : _clean(label.getAttribute('title') ?? '');
}
