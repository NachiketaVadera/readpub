import 'dart:io';
import 'dart:typed_data';

import '../error/publication_exception.dart';

/// A readable input to a publication.
///
/// Ranges are zero-based and half-open: `[start, end)`. Omitting `end` reads
/// through the end of the asset.
abstract interface class Asset {
  /// A display name for the asset, if it has one.
  String? get name;

  /// The asset length in bytes, if it is known without reading it.
  Future<int?> get length;

  /// Reads bytes in the requested half-open range.
  Future<Uint8List> read({int? start, int? end});
}

/// An [Asset] backed by immutable bytes held in memory.
final class MemoryAsset implements Asset {
  /// Creates an in-memory asset.
  ///
  /// The input is copied so subsequent changes to it cannot change the asset.
  MemoryAsset(List<int> bytes, {this.name}) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  @override
  final String? name;

  @override
  Future<int?> get length async => _bytes.length;

  @override
  Future<Uint8List> read({int? start, int? end}) async {
    final range = _validatedRange(_bytes.length, start: start, end: end);
    return Uint8List.fromList(_bytes.sublist(range.start, range.end));
  }
}

/// An [Asset] backed by a local file.
///
/// File reads keep ZIP entry access lazy and use asynchronous `dart:io` APIs.
/// Callers handling very large files should run reads outside a UI-critical
/// isolate when necessary.
final class FileAsset implements Asset {
  /// Creates an asset for [path].
  FileAsset(this.path, {String? name}) : name = name ?? _fileName(path);

  /// The path of the local input file.
  final String path;

  @override
  final String? name;

  File get _file => File(path);

  @override
  Future<int?> get length async {
    try {
      return await _file.length();
    } on FileSystemException catch (error) {
      throw AssetException('Could not read asset length.', path: path, cause: error);
    }
  }

  @override
  Future<Uint8List> read({int? start, int? end}) async {
    try {
      final fileLength = await _file.length();
      final range = _validatedRange(fileLength, start: start, end: end);
      final handle = await _file.open();
      try {
        await handle.setPosition(range.start);
        final bytes = BytesBuilder(copy: false);
        var remaining = range.end - range.start;
        while (remaining > 0) {
          final chunk = await handle.read(remaining);
          if (chunk.isEmpty) {
            throw AssetException('File ended before the requested range.', path: path);
          }
          bytes.add(chunk);
          remaining -= chunk.length;
        }
        return bytes.toBytes();
      } finally {
        await handle.close();
      }
    } on AssetException {
      rethrow;
    } on FileSystemException catch (error) {
      throw AssetException('Could not read asset.', path: path, cause: error);
    }
  }
}

({int start, int end}) _validatedRange(int length, {int? start, int? end}) {
  final actualStart = start ?? 0;
  final actualEnd = end ?? length;
  if (actualStart < 0 || actualEnd < actualStart || actualEnd > length) {
    throw AssetException(
      'Invalid byte range [$actualStart, $actualEnd) for an asset of $length bytes.',
    );
  }
  return (start: actualStart, end: actualEnd);
}

String _fileName(String path) {
  final separator = path.lastIndexOf(Platform.pathSeparator);
  return separator == -1 ? path : path.substring(separator + 1);
}
