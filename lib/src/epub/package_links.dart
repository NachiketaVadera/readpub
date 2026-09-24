part of 'epub_publication.dart';

extension _PackageLinks on _PackageReader {
  List<Link> _metadataLinks(XmlElement parent) => [
    for (final node in parent.childElements.where((e) => _matches(e, 'link', _opfNs)))
      if (node.getAttribute('href') case final href?)
        Link(
          href: _resolveHref(href, opfPath, element: node, warnings: parser.warnings),
          type: node.getAttribute('media-type'),
          rels: _tokens(node.getAttribute('rel')),
          properties: {
            for (final name in ['properties', 'refines', 'hreflang'])
              name: ?node.getAttribute(name),
          },
        ),
  ];

  List<Link> _guide() {
    final guide = _first('guide');
    if (guide == null) return const [];
    return [
      for (final node in guide.childElements.where(
        (e) => _matches(e, 'reference', _opfNs),
      ))
        if (node.getAttribute('href') case final href?)
          Link(
            href: _resolveHref(href, opfPath, element: node, warnings: parser.warnings),
            title: node.getAttribute('title'),
            rels: _tokens(node.getAttribute('type')).map(
              (type) => switch (type) {
                'text' => 'bodymatter',
                'toc' => 'contents',
                _ => type,
              },
            ),
          ),
    ];
  }

  List<PublicationCollection> _collections(_MetadataReader meta) {
    PublicationCollection decode(XmlElement collection) {
      final metadata = collection.childElements.firstWhereOrNull(
        (e) => _matches(e, 'metadata', _opfNs),
      );
      return PublicationCollection(
        role: collection.getAttribute('role') ?? 'unknown',
        links: _metadataLinks(collection),
        metadata: metadata == null
            ? const []
            : _metadataRecords(metadata, meta.prefixes),
        children: [
          for (final child in collection.childElements.where(
            (e) => _matches(e, 'collection', _opfNs),
          ))
            decode(child),
        ],
      );
    }

    return [
      for (final node in document.rootElement.childElements.where(
        (e) => _matches(e, 'collection', _opfNs),
      ))
        decode(node),
    ];
  }

  List<PublicationCollection> _bindings(
    Map<String, _ManifestItem> items,
    Map<String, Link> links,
  ) {
    final bindings = _first('bindings');
    if (bindings == null) return const [];
    final result = <Link>[];
    final seen = <String>{};
    for (final node in bindings.childElements.where(
      (e) => _matches(e, 'mediaType', _opfNs),
    )) {
      final mediaType = node.getAttribute('media-type');
      final handler = node.getAttribute('handler');
      final item = items[handler];
      final link = links[handler];
      if (mediaType == null ||
          !seen.add(mediaType) ||
          item == null ||
          link == null ||
          item.type != 'application/xhtml+xml' ||
          item.external) {
        throw EpubException('Invalid EPUB binding handler.', path: opfPath);
      }
      result.add(
        _copyLink(
          link,
          rels: {...link.rels, 'handler'},
          properties: {...link.properties, 'handles': mediaType},
        ),
      );
    }
    return result.isEmpty
        ? const []
        : [PublicationCollection(role: 'bindings', links: result)];
  }
}
