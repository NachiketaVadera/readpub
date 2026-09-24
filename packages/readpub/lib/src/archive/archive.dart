import 'dart:typed_data';

/// Limits applied while indexing and reading an untrusted ZIP archive.
final class ArchiveLimits {
  /// Creates archive limits.
  const ArchiveLimits({
    this.maxArchiveSize = 1024 * 1024 * 1024,
    this.maxCentralDirectorySize = 16 * 1024 * 1024,
    this.maxEntries = 10000,
    this.maxCompressedEntrySize = 64 * 1024 * 1024,
    this.maxEntrySize = 64 * 1024 * 1024,
    this.maxTotalUncompressedSize = 512 * 1024 * 1024,
    this.maxCompressionRatio = 1000,
  }) : assert(maxArchiveSize >= 22),
       assert(maxCentralDirectorySize >= 46),
       assert(maxEntries > 0),
       assert(maxCompressedEntrySize >= 0),
       assert(maxEntrySize >= 0),
       assert(maxTotalUncompressedSize >= 0),
       assert(maxCompressionRatio > 0);

  /// Maximum byte length of the ZIP input.
  final int maxArchiveSize;

  /// Maximum byte length of the ZIP central directory.
  final int maxCentralDirectorySize;

  /// Maximum number of ZIP members.
  final int maxEntries;

  /// Maximum compressed byte length of one ZIP member.
  final int maxCompressedEntrySize;

  /// Maximum actual uncompressed size of one materialized member.
  final int maxEntrySize;

  /// Maximum sum of declared uncompressed member sizes.
  final int maxTotalUncompressedSize;

  /// Maximum declared uncompressed-to-compressed size ratio.
  final int maxCompressionRatio;
}

/// A metadata record for an entry in a publication archive.
final class ArchiveEntry {
  /// Creates an archive entry record.
  const ArchiveEntry({
    required this.path,
    required this.size,
    required this.isDirectory,
  });

  /// The canonical publication-relative path.
  final String path;

  /// The declared uncompressed byte length.
  final int size;

  /// Whether the entry is a directory.
  final bool isDirectory;

  @override
  bool operator ==(Object other) =>
      other is ArchiveEntry &&
      path == other.path &&
      size == other.size &&
      isDirectory == other.isDirectory;

  @override
  int get hashCode => Object.hash(path, size, isDirectory);

  @override
  String toString() => 'ArchiveEntry($path, $size bytes, directory: $isDirectory)';
}

/// A source of files inside a publication container.
abstract interface class Archive {
  /// The archive members, indexed when the archive is opened.
  Iterable<ArchiveEntry> get entries;

  /// Gets metadata for a canonical archive [path], if it exists.
  ArchiveEntry? entry(String path);

  /// Reads the full entry or a half-open byte range from it.
  Future<Uint8List> read(String path, {int? start, int? end});

  /// Releases resources held by the archive.
  Future<void> close();
}
