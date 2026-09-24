/// Base class for failures raised while accessing a publication.
sealed class PublicationException implements Exception {
  /// Creates a publication failure with a diagnostic [message].
  const PublicationException(this.message, {this.path, this.cause});

  /// A human-readable description of the failure.
  final String message;

  /// The publication-relative path involved in the failure, if known.
  final String? path;

  /// The underlying error, if one was reported by a dependency or the system.
  final Object? cause;

  @override
  String toString() {
    final location = path == null ? '' : ' ($path)';
    return '$runtimeType: $message$location';
  }
}

/// A failure while reading a publication input asset.
final class AssetException extends PublicationException {
  /// Creates an asset failure.
  const AssetException(super.message, {super.path, super.cause});
}

/// A failure while opening or reading an archive.
final class ArchiveException extends PublicationException {
  /// Creates an archive failure.
  const ArchiveException(super.message, {super.path, super.cause});
}

/// A failure while resolving or reading a publication resource.
final class ResourceException extends PublicationException {
  /// Creates a resource failure.
  const ResourceException(super.message, {super.path, super.cause});
}

/// A failure while interpreting an EPUB package document or navigation file.
final class EpubException extends PublicationException {
  /// Creates an EPUB parsing failure.
  const EpubException(super.message, {super.path, super.cause});
}

/// An EPUB input violates a security boundary.
final class EpubSecurityException extends PublicationException {
  /// Creates an EPUB security failure.
  const EpubSecurityException(super.message, {super.path, super.cause});
}

/// An EPUB input exceeds a configured processing limit.
final class EpubLimitException extends PublicationException {
  /// Creates an EPUB processing-limit failure.
  const EpubLimitException(super.message, {super.path, super.cause});
}

/// A content document cannot be decoded or parsed within configured limits.
final class ContentException extends PublicationException {
  /// Creates a content-document failure.
  const ContentException(super.message, {super.path, super.cause});
}
