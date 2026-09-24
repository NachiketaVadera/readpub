part of 'zip_archive.dart';

final class _EndOfCentralDirectory {
  const _EndOfCentralDirectory(
    this.entryCount,
    this.directorySize,
    this.directoryOffset,
    this.offset,
  );

  final int entryCount;
  final int directorySize;
  final int directoryOffset;
  final int offset;
}

_EndOfCentralDirectory _findEndOfCentralDirectory(Uint8List tail) {
  for (var offset = tail.length - 22; offset >= 0; offset--) {
    if (_u32At(tail, offset) != _endOfCentralDirectorySignature) continue;
    final reader = _Reader(tail, offset: offset + 4);
    final disk = reader.u16();
    final directoryDisk = reader.u16();
    final diskEntries = reader.u16();
    final entries = reader.u16();
    final size = reader.u32();
    final directoryOffset = reader.u32();
    final commentLength = reader.u16();
    if (offset + 22 + commentLength != tail.length) continue;
    if (disk != 0 || directoryDisk != 0 || diskEntries != entries) {
      throw const ArchiveException('Multi-disk ZIP archives are not supported.');
    }
    if (entries == 0xffff || size == 0xffffffff || directoryOffset == 0xffffffff) {
      throw const ArchiveException('ZIP64 archives are not supported.');
    }
    return _EndOfCentralDirectory(entries, size, directoryOffset, offset);
  }
  throw const ArchiveException('ZIP end-of-central-directory record was not found.');
}

Map<String, _ZipRecord> _readDirectory(
  Uint8List bytes,
  _EndOfCentralDirectory end,
  ArchiveLimits limits,
) {
  final reader = _Reader(bytes);
  final records = <String, _ZipRecord>{};
  var totalSize = 0;
  for (var index = 0; index < end.entryCount; index++) {
    if (reader.remaining < 46 || reader.u32() != _centralDirectorySignature) {
      throw const ArchiveException('ZIP central directory is malformed.');
    }
    final madeBy = reader.u16();
    final version = reader.u16();
    final flags = reader.u16();
    final method = reader.u16();
    reader.skip(4);
    final crc = reader.u32();
    final compressedSize = reader.u32();
    final size = reader.u32();
    final nameLength = reader.u16();
    final extraLength = reader.u16();
    final commentLength = reader.u16();
    final disk = reader.u16();
    reader.skip(2);
    final attributes = reader.u32();
    final localOffset = reader.u32();
    final variableLength = nameLength + extraLength + commentLength;
    if (variableLength > reader.remaining ||
        disk != 0 ||
        compressedSize == 0xffffffff ||
        size == 0xffffffff ||
        localOffset == 0xffffffff) {
      throw const ArchiveException('ZIP entry is truncated, ZIP64, or multi-disk.');
    }
    final rawName = reader.bytes(nameLength);
    reader.skip(extraLength + commentLength);
    // Bits 1 and 2 are compression options; Info-ZIP also sets them on members
    // it chooses to store, where they have no meaning.
    if (version > 20 ||
        (flags & ~0x080e) != 0 ||
        (method != _stored && method != _deflate) ||
        _isSymbolicLink(madeBy, attributes)) {
      throw const ArchiveException(
        'ZIP entry is encrypted, compressed unsupported, or a symbolic link.',
      );
    }
    final rawPath = _decodeZipName(rawName);
    final path = normalizeArchivePath(rawPath);
    final fileType = (attributes >> 16) & 0xf000;
    if ((madeBy >> 8) == 3 &&
        fileType != 0 &&
        fileType != 0x8000 &&
        fileType != 0x4000) {
      throw ArchiveException('ZIP special-file entries are unsupported.', path: path);
    }
    if (rawPath.endsWith('/') && size != 0) {
      throw ArchiveException('ZIP directory contains data.', path: path);
    }
    if (localOffset + 30 > end.directoryOffset ||
        (compressedSize == 0 && size != 0) ||
        compressedSize > limits.maxCompressedEntrySize ||
        size > limits.maxEntrySize ||
        (compressedSize > 0 && size > compressedSize * limits.maxCompressionRatio)) {
      throw ArchiveException('Archive entry exceeds configured limits.', path: path);
    }
    totalSize += size;
    if (totalSize > limits.maxTotalUncompressedSize ||
        records.containsKey(path) ||
        (method == _stored && compressedSize != size)) {
      throw ArchiveException(
        'Archive entries have unsafe sizes or duplicate paths.',
        path: path,
      );
    }
    records[path] = _ZipRecord(
      ArchiveEntry(path: path, size: size, isDirectory: rawPath.endsWith('/')),
      rawName,
      flags,
      method,
      compressedSize,
      crc,
      localOffset,
    );
  }
  if (reader.remaining != 0) {
    throw const ArchiveException('ZIP central directory has trailing data.');
  }
  return records;
}

final class _ZipRecord {
  const _ZipRecord(
    this.entry,
    this.rawName,
    this.flags,
    this.compressionMethod,
    this.compressedSize,
    this.crc32,
    this.localHeaderOffset,
  );

  final ArchiveEntry entry;
  final Uint8List rawName;
  final int flags;
  final int compressionMethod;
  final int compressedSize;
  final int crc32;
  final int localHeaderOffset;
  String get path => entry.path;
}

final class _Reader {
  _Reader(this._bytes, {this._offset = 0});
  final Uint8List _bytes;
  int _offset;
  int get remaining => _bytes.length - _offset;
  int u16() {
    _require(2);
    return _bytes[_offset++] | (_bytes[_offset++] << 8);
  }

  int u32() {
    _require(4);
    return _bytes[_offset++] |
        (_bytes[_offset++] << 8) |
        (_bytes[_offset++] << 16) |
        (_bytes[_offset++] << 24);
  }

  Uint8List bytes(int count) {
    _require(count);
    final value = Uint8List.fromList(_bytes.sublist(_offset, _offset + count));
    _offset += count;
    return value;
  }

  void skip(int count) {
    _require(count);
    _offset += count;
  }

  void _require(int count) {
    if (count < 0 || count > remaining) {
      throw const ArchiveException('ZIP structure is truncated.');
    }
  }
}

final class _BoundedByteSink extends ByteConversionSinkBase {
  _BoundedByteSink(this._limit, this._path);
  final int _limit;
  final String _path;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  var _length = 0;
  var _closed = false;

  Uint8List get bytes {
    if (!_closed) throw StateError('The ZIP output sink has not been closed.');
    return _builder.takeBytes();
  }

  @override
  void add(List<int> chunk) {
    if (_closed) throw StateError('Cannot add to a closed ZIP output sink.');
    if (_length > _limit - chunk.length) {
      throw ArchiveException(
        'Archive entry exceeds the actual output size limit.',
        path: _path,
      );
    }
    _builder.add(chunk);
    _length += chunk.length;
  }

  @override
  void close() => _closed = true;
}

({int start, int end}) _range(
  int length, {
  int? start,
  int? end,
  required String path,
}) {
  final actualStart = start ?? 0;
  final actualEnd = end ?? length;
  if (actualStart < 0 || actualEnd < actualStart || actualEnd > length) {
    throw ArchiveException(
      'Invalid byte range [$actualStart, $actualEnd).',
      path: path,
    );
  }
  return (start: actualStart, end: actualEnd);
}

// OCF requires UTF-8 names, including archives whose writer omitted bit 11.
String _decodeZipName(Uint8List bytes) => utf8.decode(bytes, allowMalformed: false);

bool _isSymbolicLink(int madeBy, int attributes) =>
    (madeBy >> 8) == 3 && ((attributes >> 16) & 0xf000) == 0xa000;
bool _bytesEqual(Uint8List left, Uint8List right) =>
    left.length == right.length &&
    Iterable<int>.generate(
      left.length,
      (index) => index,
    ).every((index) => left[index] == right[index]);
int _u32At(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
// Slicing-by-8 CRC-32 (IEEE 802.3, reflected), eight bytes per iteration.
final List<Uint32List> _crcTables = () {
  final tables = List.generate(8, (_) => Uint32List(256));
  for (var n = 0; n < 256; n++) {
    var crc = n;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320;
    }
    tables[0][n] = crc;
  }
  for (var n = 0; n < 256; n++) {
    var crc = tables[0][n];
    for (var table = 1; table < 8; table++) {
      crc = tables[0][crc & 0xff] ^ (crc >> 8);
      tables[table][n] = crc;
    }
  }
  return tables;
}();

int _crc32(Uint8List bytes) => _crc32Finish(_crc32Update(_crc32Start, bytes));

const _crc32Start = 0xffffffff;

int _crc32Finish(int crc) => (crc ^ 0xffffffff) & 0xffffffff;

/// Adds [bytes] to a running CRC-32 register started at [_crc32Start].
int _crc32Update(int register, Uint8List bytes) {
  final [t0, t1, t2, t3, t4, t5, t6, t7] = _crcTables;
  var crc = register;
  var i = 0;
  final length = bytes.length;
  for (; length - i >= 8; i += 8) {
    final word =
        crc ^
        (bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16) | (bytes[i + 3] << 24));
    crc =
        t7[word & 0xff] ^
        t6[(word >> 8) & 0xff] ^
        t5[(word >> 16) & 0xff] ^
        t4[(word >> 24) & 0xff] ^
        t3[bytes[i + 4]] ^
        t2[bytes[i + 5]] ^
        t1[bytes[i + 6]] ^
        t0[bytes[i + 7]];
  }
  for (; i < length; i++) {
    crc = t0[(crc ^ bytes[i]) & 0xff] ^ (crc >> 8);
  }
  return crc;
}

const _stored = 0,
    _deflate = 8,
    _localFileHeaderSignature = 0x04034b50,
    _centralDirectorySignature = 0x02014b50,
    _endOfCentralDirectorySignature = 0x06054b50;
