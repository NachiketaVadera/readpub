part of 'epub_publication.dart';

String _uri(String path) => Uri(path: path).toString();

String _resolveRoot(String reference) {
  try {
    return resolvePublicationReference(reference);
  } on ResourceException catch (error) {
    throw EpubSecurityException(
      'Invalid EPUB resource reference.',
      path: reference,
      cause: error,
    );
  }
}

String _pathFromHref(String href) => _resolveRoot(href);

/// Resolves [reference] from a document, applying inherited `xml:base`.
///
/// Local references resolve against the container root URL defined by EPUB
/// Reading Systems 3.3: excess `..` segments stop at the root and path-absolute
/// references start at the root, so no reference can leave the container.
/// Such references are reported to [warnings] because EPUB creators must not
/// use them.
String _resolveHref(
  String reference,
  String documentPath, {
  XmlElement? element,
  List<EpubWarning>? warnings,
}) {
  var base = _uri(documentPath);
  final ancestors = <XmlElement>[];
  for (XmlNode? node = element; node != null; node = node.parent) {
    if (node is XmlElement) ancestors.add(node);
  }
  for (final node in ancestors.reversed) {
    final xmlBase = node.getAttribute('base', namespaceUri: _xmlNs);
    if (xmlBase != null && xmlBase.isNotEmpty) {
      base = _against(xmlBase, base, warnings, documentPath);
    }
  }
  return _against(reference, base, warnings, documentPath);
}

final _containerRoot = Uri.parse('https://container.invalid/');

String _against(
  String reference,
  String base, [
  List<EpubWarning>? warnings,
  String? documentPath,
]) {
  if (reference.contains(RegExp(r'[\x00-\x1f\x7f-\x9f\\]')) ||
      RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(reference)) {
    throw EpubSecurityException('Invalid characters in EPUB URI.', path: reference);
  }
  try {
    final target = Uri.parse(reference);
    final baseUri = Uri.parse(base);
    if (target.hasAuthority && !target.hasScheme) {
      throw EpubSecurityException(
        'Scheme-relative resource URI is unsupported.',
        path: reference,
      );
    }
    if (target.hasScheme || baseUri.hasScheme) {
      final resolved = baseUri.resolveUri(target);
      if (!{'https', 'http'}.contains(resolved.scheme) || !resolved.hasAuthority) {
        throw EpubSecurityException('Resource URI scheme is unsafe.', path: reference);
      }
      return resolved.toString();
    }
    if (target.path.startsWith('/')) {
      warnings?.add(
        EpubWarning(
          'url-path-absolute',
          'Path-absolute URL resolved against the container root.',
          path: documentPath ?? reference,
        ),
      );
    } else if (_leaks(reference, baseUri)) {
      warnings?.add(
        EpubWarning(
          'url-leaks-container',
          'Relative URL leaving the container was resolved at its root.',
          path: documentPath ?? reference,
        ),
      );
    }
    // RFC 3986 dot-segment removal stops at the root of the synthetic
    // container URL, which has the container root URL properties required
    // by EPUB Reading Systems 3.3.
    final resolved = _containerRoot.resolveUri(baseUri).resolveUri(target);
    final href = resolved.toString().substring(_containerRoot.toString().length);
    resolvePublicationReference(href);
    return href;
  } on ResourceException catch (error) {
    throw EpubSecurityException(
      'Resource URI cannot be resolved in the publication.',
      path: reference,
      cause: error,
    );
  } on FormatException catch (error) {
    throw EpubSecurityException('Malformed EPUB URI.', path: reference, cause: error);
  }
}

/// Whether a relative reference has more `..` segments than its base depth.
bool _leaks(String reference, Uri base) {
  final basePath = base.path.endsWith('/') ? '${base.path}__base__' : base.path;
  final rawPath = reference.split(RegExp('[?#]')).first;
  final checkPath = rawPath.endsWith('/')
      ? '${rawPath}__base__'
      : rawPath == '.' || rawPath == '..'
      ? '$rawPath/__base__'
      : rawPath;
  if (checkPath.isEmpty) return false;
  try {
    resolvePublicationReference(checkPath, basePath: basePath);
    return false;
  } on ResourceException catch (error) {
    return error.message.contains('escapes');
  }
}
