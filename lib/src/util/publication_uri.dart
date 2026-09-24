import '../error/publication_exception.dart';

/// Canonicalizes a literal ZIP entry name.
///
/// ZIP names are not URI paths. Percent signs remain literal. Benign dot
/// segments are normalized, while root escapes, absolute paths, Windows
/// separators, and controls are rejected.
String normalizeArchivePath(String path) {
  if (path.isEmpty ||
      _containsControl(path) ||
      path.startsWith('/') ||
      path.contains('\\')) {
    throw ArchiveException('Archive entry path is unsafe.', path: path);
  }
  final normalized = <String>[];
  for (final segment in path.split('/')) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (normalized.isEmpty) {
          throw ArchiveException('Archive entry path escapes its root.', path: path);
        }
        normalized.removeLast();
      default:
        if (_looksLikeWindowsDrive(segment)) {
          throw ArchiveException('Archive entry path is absolute.', path: path);
        }
        normalized.add(segment);
    }
  }
  if (normalized.isEmpty) {
    throw ArchiveException('Archive entry path has no file name.', path: path);
  }
  return normalized.join('/');
}

/// Resolves a publication-relative URI path to a canonical archive path.
///
/// The URI query and fragment are ignored for lookup. Each URI segment is
/// percent-decoded exactly once. Encoded slashes and backslashes are rejected.
String resolvePublicationPath(Uri href) {
  return resolvePublicationReference(href.toString());
}

/// Resolves a raw local URI [reference] against an optional document [basePath].
///
/// This helper preserves and validates the original percent escapes before URI
/// parsing can normalize them. Query and fragment data remain part of the URI
/// identity but never select different archive bytes. [basePath] is a
/// percent-encoded URI path to a document, not a decoded archive entry name.
/// For strict validation of original input, use this method before [Uri.parse].
String resolvePublicationReference(String reference, {String? basePath}) {
  final lookup = reference.split(RegExp('[?#]')).first;
  if ((lookup.isEmpty && basePath == null) ||
      lookup.startsWith('/') ||
      lookup.contains('\\') ||
      RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(lookup) ||
      lookup.startsWith('//')) {
    throw ResourceException(
      'Resource URI must be publication-relative.',
      path: reference,
    );
  }
  if (basePath != null) {
    if (_containsControl(basePath) ||
        basePath.contains(RegExp('[?#]')) ||
        basePath.startsWith('/') ||
        basePath.contains('\\') ||
        RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(basePath)) {
      throw ResourceException('Resource URI base path is invalid.', path: basePath);
    }
    final resolvedBase = resolvePublicationReference(basePath);
    if (lookup.isEmpty) return resolvedBase;
  }
  final rawPath = basePath == null ? lookup : '${_baseDirectory(basePath)}/$lookup';
  final resolved = <String>[];
  for (final rawSegment in rawPath.split('/')) {
    final segment = _decodeSegment(rawSegment, reference);
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (resolved.isEmpty) {
          throw ResourceException(
            'Resource URI escapes the publication root.',
            path: reference,
          );
        }
        resolved.removeLast();
      default:
        if (_looksLikeWindowsDrive(segment)) {
          throw ResourceException('Resource URI is absolute.', path: reference);
        }
        resolved.add(segment);
    }
  }
  if (resolved.isEmpty) {
    throw ResourceException('Resource URI has no file path.', path: reference);
  }
  return resolved.join('/');
}

String _decodeSegment(String segment, String reference) {
  try {
    // Dart's percent decoder expects ASCII when escapes are present. Encode
    // literal Unicode first while preserving existing escapes for one decode.
    final ascii = segment.runes
        .map(
          (rune) => rune > 0x7f
              ? Uri.encodeComponent(String.fromCharCode(rune))
              : String.fromCharCode(rune),
        )
        .join();
    final decoded = Uri.decodeComponent(ascii);
    if (decoded.contains('/') || decoded.contains('\\') || _containsControl(decoded)) {
      throw ResourceException(
        'Resource URI contains an encoded path separator.',
        path: reference,
      );
    }
    return decoded;
  } on ArgumentError catch (error) {
    throw ResourceException(
      'Resource URI has invalid percent encoding.',
      path: reference,
      cause: error,
    );
  }
}

String _baseDirectory(String path) {
  final slash = path.lastIndexOf('/');
  return slash == -1 ? '' : path.substring(0, slash);
}

bool _looksLikeWindowsDrive(String segment) =>
    segment.length >= 2 &&
    segment.codeUnitAt(1) == 58 &&
    ((segment.codeUnitAt(0) >= 65 && segment.codeUnitAt(0) <= 90) ||
        (segment.codeUnitAt(0) >= 97 && segment.codeUnitAt(0) <= 122));

bool _containsControl(String value) => value.codeUnits.any(
  (unit) => unit <= 0x1f || unit == 0x7f || (unit >= 0x80 && unit <= 0x9f),
);
