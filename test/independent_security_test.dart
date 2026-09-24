import 'dart:io';
import 'dart:typed_data';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

Future<Uint8List> fixture() =>
    File('test/fixtures/independent-python.zip').readAsBytes();

int signature(Uint8List bytes, int value, [int start = 0]) {
  final data = ByteData.sublistView(bytes);
  for (var offset = start; offset <= bytes.length - 4; offset++) {
    if (data.getUint32(offset, Endian.little) == value) return offset;
  }
  throw StateError('Test fixture signature missing.');
}

Future<void> readAll(Uint8List bytes) async {
  final archive = await ZipArchive.open(MemoryAsset(bytes));
  try {
    for (final entry in archive.entries) {
      if (!entry.isDirectory) await archive.read(entry.path);
    }
  } finally {
    await archive.close();
  }
}

void main() {
  final mutations = <String, void Function(Uint8List, ByteData, int, int)>{
    'matching forged CRC fields still fail content integrity':
        (bytes, data, central, end) {
          data.setUint32(14, 0, Endian.little);
          data.setUint32(central + 16, 0, Endian.little);
        },
    'local CRC disagrees with central': (bytes, data, central, end) =>
        data.setUint32(14, 0, Endian.little),
    'local size disagrees with central': (bytes, data, central, end) =>
        data.setUint32(22, 1, Endian.little),
    'local method disagrees with central': (bytes, data, central, end) =>
        data.setUint16(8, 8, Endian.little),
    'local filename disagrees with central': (bytes, data, central, end) =>
        bytes[30] = 88,
    'directory count is forged': (bytes, data, central, end) {
      data.setUint16(end + 8, 0, Endian.little);
      data.setUint16(end + 10, 0, Endian.little);
    },
    'directory allocation is excessive': (bytes, data, central, end) =>
        data.setUint32(end + 12, 0xffffff00, Endian.little),
    'member local offset is outside data area': (bytes, data, central, end) =>
        data.setUint32(central + 42, 0xffffff00, Endian.little),
    'member overlaps central directory': (bytes, data, central, end) =>
        data.setUint16(28, 65000, Endian.little),
    'strong encryption flag is rejected': (bytes, data, central, end) =>
        data.setUint16(central + 8, 64, Endian.little),
    'ZIP64 sentinel is rejected': (bytes, data, central, end) =>
        data.setUint32(end + 12, 0xffffffff, Endian.little),
    'split archive is rejected': (bytes, data, central, end) =>
        data.setUint16(end + 4, 1, Endian.little),
    'symlink is rejected': (bytes, data, central, end) {
      data.setUint16(central + 4, 3 << 8, Endian.little);
      data.setUint32(central + 38, 0xa1ff << 16, Endian.little);
    },
    'forged output size is bounded during decompression': (bytes, data, central, end) {
      final second = signature(bytes, 0x02014b50, central + 4);
      final local = data.getUint32(second + 42, Endian.little);
      data.setUint32(second + 24, 1, Endian.little);
      data.setUint32(local + 22, 1, Endian.little);
    },
  };
  for (final mutation in mutations.entries) {
    test(mutation.key, () async {
      final bytes = await fixture();
      mutation.value(
        bytes,
        ByteData.sublistView(bytes),
        signature(bytes, 0x02014b50),
        signature(bytes, 0x06054b50),
      );
      await expectLater(readAll(bytes), throwsA(isA<PublicationException>()));
    });
  }

  test('rejects a forged data descriptor', () async {
    final bytes = await File('test/fixtures/independent-descriptors.zip').readAsBytes();
    final offset = signature(bytes, 0x08074b50);
    bytes[offset + 4] ^= 1;
    await expectLater(readAll(bytes), throwsA(isA<ArchiveException>()));
  });

  test('enforces compressed and aggregate entry limits', () async {
    final bytes = await fixture();
    for (final limits in [
      const ArchiveLimits(maxCompressedEntrySize: 1),
      const ArchiveLimits(maxTotalUncompressedSize: 1),
    ]) {
      await expectLater(
        ZipArchive.open(MemoryAsset(bytes), limits: limits),
        throwsA(isA<ArchiveException>()),
      );
    }
  });

  test('unknown asset length fails without materializing input', () async {
    final asset = UnknownAsset();
    await expectLater(ZipArchive.open(asset), throwsA(isA<ArchiveException>()));
    expect(asset.reads, 0);
  });

  test('input and directory limits apply before large range reads', () async {
    final bytes = await fixture();
    await expectLater(
      ZipArchive.open(
        MemoryAsset(bytes),
        limits: const ArchiveLimits(maxArchiveSize: 22),
      ),
      throwsA(isA<ArchiveException>()),
    );
    await expectLater(
      ZipArchive.open(
        MemoryAsset(bytes),
        limits: const ArchiveLimits(maxCentralDirectorySize: 46),
      ),
      throwsA(isA<ArchiveException>()),
    );
  });
}

final class UnknownAsset implements Asset {
  int reads = 0;
  @override
  String? get name => null;
  @override
  Future<int?> get length async => null;
  @override
  Future<Uint8List> read({int? start, int? end}) async {
    reads++;
    throw StateError('An unknown-length input must not be materialized.');
  }
}
