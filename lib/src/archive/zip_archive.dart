import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import '../asset/asset.dart';
import '../error/publication_exception.dart';
import '../util/publication_uri.dart';
import 'archive.dart';

part 'zip_structures.dart';

/// A lazily readable ZIP32 [Archive].
///
/// It supports unencrypted stored and DEFLATE entries in single-disk archives.
/// ZIP64, encrypted archives, and other compression methods are rejected.
final class ZipArchive implements Archive {
  ZipArchive._(
    this._asset,
    this._entries,
    this._records,
    this._limits,
    this._directoryOffset,
  );

  final Asset _asset;
  final Map<String, ArchiveEntry> _entries;
  final Map<String, _ZipRecord> _records;
  final ArchiveLimits _limits;
  final int _directoryOffset;
  bool _closed = false;

  // Validated local data offsets, and stored entries whose complete bytes
  // have passed CRC verification and may be read by range thereafter.
  final Map<String, int> _dataOffsets = {};
  final Set<String> _verifiedStored = {};

  /// Opens a ZIP32 [asset] without materializing file-backed entry contents.
  static Future<ZipArchive> open(
    Asset asset, {
    ArchiveLimits limits = const ArchiveLimits(),
  }) async {
    try {
      if (limits.maxArchiveSize < 22 ||
          limits.maxCentralDirectorySize < 46 ||
          limits.maxEntries <= 0 ||
          limits.maxCompressedEntrySize < 0 ||
          limits.maxEntrySize < 0 ||
          limits.maxTotalUncompressedSize < 0 ||
          limits.maxCompressionRatio <= 0) {
        throw const ArchiveException('Archive limits are invalid.');
      }
      final knownLength = await asset.length;
      if (knownLength != null && knownLength > limits.maxArchiveSize) {
        throw const ArchiveException('Archive input exceeds the size limit.');
      }
      if (knownLength == null) {
        throw const ArchiveException('Archive input length must be known.');
      }
      final length = knownLength;
      if (length < 22 || length > limits.maxArchiveSize) {
        throw const ArchiveException(
          'Archive input is malformed or exceeds the size limit.',
        );
      }
      final tailLength = length < 65557 ? length : 65557;
      final tail = await asset.read(start: length - tailLength, end: length);
      if (tail.length != tailLength) {
        throw const ArchiveException('Asset returned an incomplete ZIP tail.');
      }
      final end = _findEndOfCentralDirectory(tail);
      if (end.directorySize > limits.maxCentralDirectorySize ||
          end.entryCount > limits.maxEntries ||
          end.directoryOffset + end.directorySize != length - tailLength + end.offset) {
        throw const ArchiveException(
          'Archive central directory exceeds configured limits.',
        );
      }
      final directory = await asset.read(
        start: end.directoryOffset,
        end: end.directoryOffset + end.directorySize,
      );
      final records = _readDirectory(directory, end, limits);
      return ZipArchive._(
        asset,
        Map.unmodifiable({
          for (final record in records.values) record.path: record.entry,
        }),
        Map.unmodifiable(records),
        limits,
        end.directoryOffset,
      );
    } on PublicationException {
      rethrow;
    } on Object catch (error) {
      throw ArchiveException('Could not open ZIP archive.', cause: error);
    }
  }

  @override
  Iterable<ArchiveEntry> get entries => _entries.values;

  @override
  ArchiveEntry? entry(String path) => _entries[path];

  @override
  Future<Uint8List> read(String path, {int? start, int? end}) async {
    _ensureOpen();
    final normalized = normalizeArchivePath(path);
    final record = _records[normalized];
    if (record == null || record.entry.isDirectory) {
      throw ArchiveException('Archive entry was not found.', path: normalized);
    }
    final range = _range(record.entry.size, start: start, end: end, path: normalized);
    try {
      final offset = _dataOffsets[normalized] ??= await _dataOffset(record);
      final partial = range.start != 0 || range.end != record.entry.size;
      if (record.compressionMethod == _stored &&
          partial &&
          !_verifiedStored.contains(normalized)) {
        await _verifyStored(record, offset);
      }
      if (_verifiedStored.contains(normalized)) {
        return range.start == range.end
            ? Uint8List(0)
            : await _asset.read(start: offset + range.start, end: offset + range.end);
      }
      final compressed = await _asset.read(
        start: offset,
        end: offset + record.compressedSize,
      );
      final bytes = _decompress(record, compressed);
      if (bytes.length != record.entry.size || _crc32(bytes) != record.crc32) {
        throw ArchiveException(
          'Archive entry fails its directory integrity checks.',
          path: normalized,
        );
      }
      if ((record.flags & 8) != 0) {
        await _validateDescriptor(record, offset + record.compressedSize);
      }
      if (record.compressionMethod == _stored) _verifiedStored.add(normalized);
      return bytes.sublist(range.start, range.end);
    } on PublicationException {
      rethrow;
    } on Object catch (error) {
      throw ArchiveException(
        'Could not decompress archive entry.',
        path: normalized,
        cause: error,
      );
    }
  }

  /// Verifies a stored member in bounded chunks, so a first range request for
  /// large media does not materialize the whole member.
  Future<void> _verifyStored(_ZipRecord record, int offset) async {
    const chunk = 1024 * 1024;
    var crc = _crc32Start;
    for (var start = 0; start < record.compressedSize; start += chunk) {
      final end = start + chunk < record.compressedSize
          ? start + chunk
          : record.compressedSize;
      crc = _crc32Update(
        crc,
        await _asset.read(start: offset + start, end: offset + end),
      );
    }
    if (record.compressedSize != record.entry.size ||
        _crc32Finish(crc) != record.crc32) {
      throw ArchiveException(
        'Archive entry fails its directory integrity checks.',
        path: record.path,
      );
    }
    if ((record.flags & 8) != 0) {
      await _validateDescriptor(record, offset + record.compressedSize);
    }
    _verifiedStored.add(record.path);
  }

  Future<int> _dataOffset(_ZipRecord record) async {
    final header = await _asset.read(
      start: record.localHeaderOffset,
      end: record.localHeaderOffset + 30,
    );
    final reader = _Reader(header);
    if (reader.u32() != _localFileHeaderSignature) {
      throw ArchiveException(
        'Archive entry has an invalid local header.',
        path: record.path,
      );
    }
    final version = reader.u16();
    final flags = reader.u16();
    final method = reader.u16();
    reader.skip(4);
    final crc = reader.u32();
    final compressedSize = reader.u32();
    final size = reader.u32();
    final nameLength = reader.u16();
    final extraLength = reader.u16();
    if (version > 20 ||
        flags != record.flags ||
        method != record.compressionMethod ||
        ((flags & 8) == 0 &&
            (crc != record.crc32 ||
                compressedSize != record.compressedSize ||
                size != record.entry.size))) {
      throw ArchiveException(
        'Archive entry local header differs from directory.',
        path: record.path,
      );
    }
    final dataOffset = record.localHeaderOffset + 30 + nameLength + extraLength;
    if (dataOffset + record.compressedSize > _directoryOffset) {
      throw ArchiveException(
        'ZIP member overlaps its central directory.',
        path: record.path,
      );
    }
    final name = await _asset.read(
      start: record.localHeaderOffset + 30,
      end: record.localHeaderOffset + 30 + nameLength,
    );
    if (!_bytesEqual(name, record.rawName)) {
      throw ArchiveException(
        'Archive entry local header name differs from directory.',
        path: record.path,
      );
    }
    return dataOffset;
  }

  Future<void> _validateDescriptor(_ZipRecord record, int offset) async {
    final available = _directoryOffset - offset;
    if (available < 12) {
      throw ArchiveException('ZIP data descriptor is truncated.', path: record.path);
    }
    final bytes = await _asset.read(
      start: offset,
      end: offset + (available < 16 ? 12 : 16),
    );
    bool matches(int start) =>
        bytes.length >= start + 12 &&
        _u32At(bytes, start) == record.crc32 &&
        _u32At(bytes, start + 4) == record.compressedSize &&
        _u32At(bytes, start + 8) == record.entry.size;
    if (!matches(0) && !(_u32At(bytes, 0) == 0x08074b50 && matches(4))) {
      throw ArchiveException(
        'ZIP data descriptor disagrees with directory.',
        path: record.path,
      );
    }
  }

  Uint8List _decompress(_ZipRecord record, Uint8List compressed) {
    final output = _BoundedByteSink(
      record.entry.size < _limits.maxEntrySize
          ? record.entry.size
          : _limits.maxEntrySize,
      record.path,
    );
    if (record.compressionMethod == _stored) {
      output.add(compressed);
      output.close();
    } else {
      final converter = ZLibDecoder(raw: true).startChunkedConversion(output);
      // Small compressed chunks bound intermediate decoder allocations as well
      // as the retained output controlled by the sink.
      for (var start = 0; start < compressed.length; start += 1024) {
        final end = start + 1024 < compressed.length ? start + 1024 : compressed.length;
        converter.add(Uint8List.sublistView(compressed, start, end));
      }
      converter.close();
    }
    return output.bytes;
  }

  @override
  Future<void> close() async => _closed = true;

  void _ensureOpen() {
    if (_closed) {
      throw const ArchiveException('Archive is closed.');
    }
  }
}
