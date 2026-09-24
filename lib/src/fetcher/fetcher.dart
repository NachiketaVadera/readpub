/// @docImport '../error/publication_exception.dart';
library;

import '../resource/resource.dart';

/// Resolves publication-relative resources without exposing their storage.
abstract interface class Fetcher {
  /// Gets a resource when [href] resolves to an available publication member.
  Future<Resource?> get(Uri href);

  /// Opens [href] or throws a [ResourceException] when it is unavailable.
  Future<Resource> open(Uri href);

  /// Releases resources held by this fetcher.
  Future<void> close();
}
