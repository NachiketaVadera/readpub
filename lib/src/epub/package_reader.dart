part of 'epub_publication.dart';

typedef _PackageData = ({
  Metadata metadata,
  String? uniqueIdentifier,
  List<Link> links,
  List<Link> publicationLinks,
  List<Link> readingOrder,
  List<Link> resources,
  List<Link> toc,
  List<Link> landmarks,
  List<Link> pageList,
  List<PublicationCollection> collections,
  List<EpubSpineItem> spine,
});

final class _PackageReader {
  _PackageReader(this.document, this.opfPath, this.parser);
  final XmlDocument document;
  final String opfPath;
  final _EpubParser parser;

  XmlElement? _first(String name) => document.rootElement.childElements
      .firstWhereOrNull((e) => _matches(e, name, _opfNs));

  Future<_PackageData> read() async {
    // Reading systems must attempt to process packages whose version is below
    // 3.0 (EPUB Reading Systems 3.3); unknown versions are processed as well.
    final version = document.rootElement.getAttribute('version');
    if (version == null || !RegExp(r'^[23]\.\d+(\.\d+)?$').hasMatch(version)) {
      parser.warnings.add(
        EpubWarning(
          'package-version-unsupported',
          'Processing package with version ${version ?? '(missing)'} as EPUB 3.',
          path: opfPath,
        ),
      );
    }
    final metadataElement = _first('metadata');
    final manifest = _first('manifest');
    final spine = _first('spine');
    if (metadataElement == null || manifest == null || spine == null) {
      throw EpubException(
        'Package requires metadata, manifest, and spine.',
        path: opfPath,
      );
    }
    final meta = _MetadataReader(
      metadataElement,
      document.rootElement,
      parser,
      opfPath,
    );
    final items = _manifest(manifest, meta);
    final byId = _makeLinks(items, meta);
    final reading = <Link>[];
    final auxiliary = <String, Link>{};
    final linearIds = <String>{};
    final spineItems = <EpubSpineItem>[];
    // CFI steps count every child element, including foreign extensions.
    final packageChildren = document.rootElement.childElements.toList();
    final spineStep = CfiStep(
      2 * (packageChildren.indexOf(spine) + 1),
      id: _nonEmpty(spine.getAttribute('id')),
    );
    final spineChildren = spine.childElements.toList();
    for (var position = 0; position < spineChildren.length; position++) {
      final ref = spineChildren[position];
      if (!_matches(ref, 'itemref', _opfNs)) continue;
      final id = ref.getAttribute('idref');
      final item = items[id];
      final link = byId[id];
      if (item == null || link == null) {
        throw EpubException('Spine references a missing manifest item.', path: opfPath);
      }
      // A missing spine resource is reported by the manifest's resource-missing
      // warning; it may still be replaced by a manifest fallback.
      final linear = ref.getAttribute('linear')?.toLowerCase() ?? 'yes';
      if (linear != 'yes' && linear != 'no') {
        parser.warnings.add(
          EpubWarning(
            'spine-linear-invalid',
            'Treating invalid linear value as yes.',
            path: opfPath,
          ),
        );
      }
      final properties = {
        ...link.properties,
        ..._renditionProperties(_tokens(ref.getAttribute('properties')), meta.prefixes),
        'linear': linear == 'no' ? 'no' : 'yes',
      };
      final entry = _copyLink(link, properties: properties);
      spineItems.add(
        EpubSpineItem._(
          entry,
          linear != 'no',
          CfiPath([
            spineStep,
            CfiStep(2 * (position + 1), id: _nonEmpty(ref.getAttribute('id'))),
          ]),
          item.id,
        ),
      );
      if (linear == 'no') {
        auxiliary[item.id] = entry;
      } else {
        reading.add(entry);
        linearIds.add(item.id);
      }
    }
    if (reading.isEmpty) {
      throw EpubException('Publication has no linear reading order.', path: opfPath);
    }
    final cover = byId.values.where((link) => link.rels.contains('cover')).firstOrNull;
    final progression = spine.getAttribute('page-progression-direction') ?? 'auto';
    final metadata = meta.build(
      cover: cover,
      readingProgression: {'auto', 'ltr', 'rtl', 'ttb', 'btt'}.contains(progression)
          ? progression
          : 'auto',
    );
    final nav = await _navigation(items, spine);
    final guide = _guide();
    final collections = [
      ..._collections(meta),
      ...nav.collections,
      ..._bindings(items, byId),
    ];
    if (guide.isNotEmpty && nav.landmarks.isNotEmpty) {
      collections.add(PublicationCollection(role: 'guide', links: guide));
    }
    return (
      metadata: metadata,
      uniqueIdentifier: meta.uniqueIdentifier,
      links: byId.values.toList(),
      publicationLinks: _metadataLinks(metadataElement),
      readingOrder: reading,
      resources: [
        for (final item in items.values)
          if (!linearIds.contains(item.id))
            auxiliary[item.id] ?? byId[item.id] ?? item.baseLink,
      ],
      toc: nav.toc,
      landmarks: nav.landmarks.isEmpty ? guide : nav.landmarks,
      pageList: nav.pages,
      collections: collections,
      spine: spineItems,
    );
  }

  Future<_NavigationResult> _navigation(
    Map<String, _ManifestItem> items,
    XmlElement spine,
  ) async {
    var result = const _NavigationResult([], [], []);
    final nav = items.values.where((item) => item.tokens.contains('nav')).firstOrNull;
    if (nav != null) {
      try {
        result = await _NavReader(parser, nav.path, opfPath).read();
        if (result.toc.isNotEmpty) return result;
        parser.warnings.add(
          EpubWarning(
            'navigation-empty',
            'EPUB nav has no usable TOC.',
            path: nav.path,
          ),
        );
      } on EpubException catch (error) {
        parser.warnings.add(
          EpubWarning('navigation-invalid', error.message, path: nav.path),
        );
      }
    }
    final ncxId = spine.getAttribute('toc');
    final ncx =
        items[ncxId] ??
        items.values
            .where((item) => item.type == 'application/x-dtbncx+xml')
            .firstOrNull;
    if (ncx != null) {
      try {
        final legacy = await _NcxReader(parser, ncx.path, opfPath).read();
        return _NavigationResult(
          legacy.toc,
          result.landmarks,
          result.pages.isEmpty ? legacy.pages : result.pages,
          [...result.collections, ...legacy.collections],
        );
      } on EpubException catch (error) {
        parser.warnings.add(EpubWarning('ncx-invalid', error.message, path: ncx.path));
      }
    }
    parser.warnings.add(
      EpubWarning(
        'navigation-missing',
        'Publication has no usable TOC.',
        path: opfPath,
      ),
    );
    return result;
  }
}

final class _ManifestItem {
  const _ManifestItem(
    this.id,
    this.path,
    this.href,
    this.type,
    this.tokens,
    this.attributes,
    this.external,
    this.baseLink,
  );
  final String id;
  final String path;
  final String href;
  final String type;
  final Set<String> tokens;
  final Map<String, String> attributes;
  final bool external;
  final Link baseLink;
}

String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;

Set<String> _tokens(String? value) =>
    (value ?? '').split(RegExp(r'\s+')).where((v) => v.isNotEmpty).toSet();

Link _copyLink(
  Link link, {
  Map<String, String>? properties,
  Iterable<Link>? alternates,
  Iterable<String>? rels,
}) => Link(
  href: link.href,
  type: link.type,
  title: link.title,
  duration: link.duration,
  rels: rels ?? link.rels,
  properties: properties ?? link.properties,
  children: link.children,
  alternates: alternates ?? link.alternates,
);
