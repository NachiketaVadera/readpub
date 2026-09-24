import 'dart:convert';
import 'dart:typed_data';

import '../error/publication_exception.dart';

/// A readable publication resource.
///
/// Ranges are zero-based and half-open: `[start, end)`.
abstract interface class Resource {
  /// The URI used to identify this resource.
  Uri get href;

  /// The media type inferred or supplied for the resource, if known.
  String? get mediaType;

  /// The uncompressed byte length, if known.
  Future<int?> get length;

  /// Reads bytes in the requested half-open range.
  Future<Uint8List> read({int? start, int? end});
}

/// Text decoding helpers for publication resources.
extension ResourceText on Resource {
  /// Reads this resource as text using [encoding], defaulting to strict UTF-8.
  ///
  /// This materializes the resource. Pass an encoding explicitly for legacy
  /// content; this method does not interpret HTML or XML charset declarations.
  Future<String> readAsString({Encoding encoding = utf8}) async {
    final bytes = await read();
    try {
      return encoding.decode(bytes);
    } on FormatException catch (error) {
      throw ResourceException(
        'Cannot decode resource text.',
        path: href.toString(),
        cause: error,
      );
    }
  }
}
