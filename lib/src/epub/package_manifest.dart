part of 'epub_publication.dart';

extension _PackageManifest on _PackageReader {
  Map<String, _ManifestItem> _manifest(XmlElement manifest, _MetadataReader meta) {
    final items = <String, _ManifestItem>{};
    final hrefs = <String>{};
    final coverId = meta.legacy('cover');
    for (final node in manifest.childElements.where(
      (e) => _matches(e, 'item', _opfNs),
    )) {
      final id = node.getAttribute('id');
      final reference = node.getAttribute('href');
      if (id == null ||
          id.trim().isEmpty ||
          reference == null ||
          reference.isEmpty ||
          items.containsKey(id)) {
        throw EpubException(
          'Manifest item is incomplete or has a duplicate id.',
          path: opfPath,
        );
      }
      final href = _resolveHref(
        reference,
        opfPath,
        element: node,
        warnings: parser.warnings,
      );
      final external = Uri.parse(href).hasScheme;
      final path = external ? href : _pathFromHref(href);
      if (!hrefs.add(href)) {
        throw EpubException('Manifest contains duplicate resource hrefs.', path: href);
      }
      final declared = node.getAttribute('media-type');
      final type = _mediaType(declared, href);
      if (declared != type) {
        parser.warnings.add(
          EpubWarning(
            'media-type-normalized',
            'Manifest media type was normalized to $type.',
            path: path,
          ),
        );
      }
      final tokens = _tokens(node.getAttribute('properties'))
          .map((value) => _canonicalProperty(_expandProperty(value, meta.prefixes)))
          .toSet();
      if (!external &&
          (parser.archive.entry(path) == null ||
              parser.archive.entry(path)?.isDirectory == true)) {
        parser.warnings.add(
          EpubWarning('resource-missing', 'Manifest resource is absent.', path: path),
        );
      }
      final attributes = {
        for (final name in ['fallback', 'fallback-style', 'media-overlay'])
          name: ?node.getAttribute(name),
      };
      final durationSource = meta.refinement(id, 'media:duration');
      final duration = _clock(durationSource);
      if (durationSource != null && duration == null) {
        parser.warnings.add(
          EpubWarning(
            'media-duration-invalid',
            'Invalid resource duration.',
            path: path,
          ),
        );
      }
      final link = Link(
        href: href,
        type: type,
        duration: duration,
        rels: {
          if (tokens.contains('cover-image') || id == coverId) 'cover',
          if (tokens.contains('nav')) 'contents',
        },
        properties: {
          'id': id,
          if (tokens.isNotEmpty) 'properties': tokens.join(' '),
          'declared-media-type': ?declared,
          ..._renditionProperties(tokens, meta.prefixes),
        },
      );
      items[id] = _ManifestItem(
        id,
        path,
        href,
        type,
        tokens,
        attributes,
        external,
        link,
      );
    }
    if (items.isEmpty) throw EpubException('Package manifest is empty.', path: opfPath);
    return items;
  }

  Map<String, Link> _makeLinks(Map<String, _ManifestItem> items, _MetadataReader meta) {
    final completed = <String, Link>{};
    final active = <String>{};
    Link build(String id, int depth) {
      final existing = completed[id];
      if (existing != null) return existing;
      if (depth > parser.options.maxXmlDepth) {
        throw EpubLimitException(
          'Manifest association depth exceeds limit.',
          path: opfPath,
        );
      }
      final item = items[id];
      if (item == null || !active.add(id)) {
        throw EpubException(
          'Manifest fallback or overlay is missing or cyclic.',
          path: opfPath,
        );
      }
      final alternates = <Link>[];
      final properties = {...item.baseLink.properties};
      for (final kind in ['fallback', 'media-overlay']) {
        final target = item.attributes[kind];
        if (target == null) continue;
        final alternate = build(target, depth + 1);
        if (kind == 'media-overlay' && alternate.type != 'application/smil+xml') {
          throw EpubException('Media overlay target is not SMIL.', path: item.path);
        }
        alternates.add(alternate);
        properties[kind] = alternate.href;
      }
      final fallbackStyle = item.attributes['fallback-style'];
      if (fallbackStyle != null) {
        final style = items[fallbackStyle];
        if (style == null) {
          throw EpubException('Missing fallback stylesheet.', path: item.path);
        }
        properties['fallback-style'] = style.href;
      }
      final result = _copyLink(
        item.baseLink,
        properties: properties,
        alternates: alternates,
      );
      active.remove(id);
      completed[id] = result;
      return result;
    }

    // Retain manifest order even though dependency resolution visits alternates.
    return {for (final id in items.keys) id: build(id, 1)};
  }
}

Map<String, String> _renditionProperties(
  Set<String> values,
  Map<String, String> prefixes,
) {
  final result = <String, String>{};
  for (final token in values) {
    final value = _canonicalProperty(_expandProperty(token, prefixes));
    if (value.startsWith('page-spread-')) result['page'] = value.substring(12);
    if (value.startsWith('rendition:page-spread-')) {
      result['page'] = value.substring(22);
    }
    if (value == 'rendition:layout-pre-paginated') result['layout'] = 'fixed';
    if (value == 'rendition:layout-reflowable') result['layout'] = 'reflowable';
    if (value.startsWith('rendition:orientation-')) {
      result['orientation'] = value.substring(22);
    }
    if (value.startsWith('rendition:spread-')) result['spread'] = value.substring(17);
    if (value.startsWith('rendition:flow-')) result['flow'] = value.substring(15);
  }
  return result;
}

const _mediaTypes = <String, String>{
  'xhtml': 'application/xhtml+xml',
  'html': 'text/html',
  'htm': 'text/html',
  'css': 'text/css',
  'svg': 'image/svg+xml',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'avif': 'image/avif',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'mp3': 'audio/mpeg',
  'aac': 'audio/aac',
  'm4a': 'audio/mp4',
  'mp4': 'video/mp4',
  'ogg': 'audio/ogg',
  'smil': 'application/smil+xml',
  'js': 'text/javascript',
  'xml': 'application/xml',
  'opf': 'application/oebps-package+xml',
  'ncx': 'application/x-dtbncx+xml',
};
String _mediaType(String? declared, String href) {
  final value = declared?.split(';').first.trim().toLowerCase();
  final path = Uri.parse(href).path;
  final dot = path.lastIndexOf('.');
  final inferred = dot > path.lastIndexOf('/')
      ? _mediaTypes[path.substring(dot + 1).toLowerCase()]
      : null;
  if (value == 'image/jpg') return 'image/jpeg';
  if (value == 'text/xml') return inferred ?? 'application/xml';
  if (value == 'text/html' && inferred == 'application/xhtml+xml') {
    return 'application/xhtml+xml';
  }
  if (value == null ||
      value == 'application/octet-stream' ||
      !RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$').hasMatch(value)) {
    return inferred ?? 'application/octet-stream';
  }
  return value;
}
