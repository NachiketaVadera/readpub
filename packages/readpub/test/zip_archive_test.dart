import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

void main() {
  group('ZipArchive', () {
    test('reads stored and DEFLATE members, ranges, and concurrent requests', () async {
      final archive = await ZipArchive.open(
        MemoryAsset(
          _zip(<_Member>[
            _Member('mimetype', ascii.encode('application/epub+zip')),
            _Member('OPS/chapter.xhtml', utf8.encode('chapter body'), deflate: true),
            _Member('empty.txt', const <int>[]),
          ]),
        ),
      );
      addTearDown(archive.close);

      expect(archive.entries.map((entry) => entry.path), <String>[
        'mimetype',
        'OPS/chapter.xhtml',
        'empty.txt',
      ]);
      expect(
        utf8.decode(await archive.read('OPS/chapter.xhtml', start: 2, end: 9)),
        'apter b',
      );
      expect(await archive.read('empty.txt'), isEmpty);
      final reads = await Future.wait(<Future<Uint8List>>[
        archive.read('mimetype'),
        archive.read('OPS/chapter.xhtml'),
      ]);
      expect(utf8.decode(reads[0]), 'application/epub+zip');
      expect(utf8.decode(reads[1]), 'chapter body');
      expect(() => archive.read('missing'), throwsA(isA<ArchiveException>()));
      expect(() => archive.read('mimetype', end: 99), throwsA(isA<ArchiveException>()));
    });

    test('checks CRC and actual DEFLATE output limits', () async {
      final bytes = _zip(<_Member>[
        _Member('text.txt', utf8.encode('x' * 4096), deflate: true),
      ]);
      final archive = await ZipArchive.open(MemoryAsset(bytes));
      addTearDown(archive.close);
      expect(await archive.read('text.txt'), hasLength(4096));

      expect(
        ZipArchive.open(
          MemoryAsset(bytes),
          limits: const ArchiveLimits(maxEntrySize: 100),
        ),
        throwsA(isA<ArchiveException>()),
      );

      final corrupt = Uint8List.fromList(bytes)..[14] ^= 1;
      final corrupted = await ZipArchive.open(MemoryAsset(corrupt));
      addTearDown(corrupted.close);
      expect(() => corrupted.read('text.txt'), throwsA(isA<ArchiveException>()));
    });

    test('verifies stored members once, then serves ranges directly', () async {
      final payload = List<int>.generate(2600000, (index) => (index * 31) % 256);
      final bytes = _zip(<_Member>[_Member('media.bin', payload)]);
      final reads = <(int?, int?)>[];
      final archive = await ZipArchive.open(_RecordingAsset(bytes, reads));
      addTearDown(archive.close);
      reads.clear();
      expect(
        await archive.read('media.bin', start: 1000, end: 1010),
        payload.sublist(1000, 1010),
      );
      // The first range verifies the whole entry, in bounded chunks.
      final sizes = [for (final (start, end) in reads) end! - start!];
      expect(sizes.where((size) => size == 1024 * 1024), hasLength(2));
      expect(sizes.every((size) => size <= 1024 * 1024), isTrue);
      reads.clear();
      expect(
        await archive.read('media.bin', start: 2500000, end: 2500100),
        payload.sublist(2500000, 2500100),
      );
      expect(await archive.read('media.bin', start: 5, end: 5), isEmpty);
      expect(reads.every((read) => read.$2! - read.$1! <= 100), isTrue);
      expect(reads, hasLength(1));
      expect(await archive.read('media.bin'), payload);

      // A corrupted stored member fails even when only a range is requested.
      final corrupt = Uint8List.fromList(bytes);
      corrupt[corrupt.length ~/ 2] ^= 1;
      final corrupted = await ZipArchive.open(MemoryAsset(corrupt));
      addTearDown(corrupted.close);
      await expectLater(
        corrupted.read('media.bin', start: 0, end: 10),
        throwsA(isA<ArchiveException>()),
      );
      await expectLater(
        corrupted.read('media.bin', start: 0, end: 10),
        throwsA(isA<ArchiveException>()),
        reason: 'failed verification is not remembered as success',
      );
    });

    test('ignores compression option flags on stored members', () async {
      // Info-ZIP `zip -9` sets the maximum-compression option bits on members
      // it decides to store, such as already-compressed fonts.
      final archive = await ZipArchive.open(
        MemoryAsset(
          _zip(<_Member>[
            _Member('font.woff2', const [1, 2, 3], flags: 2),
          ]),
        ),
      );
      addTearDown(archive.close);
      expect(await archive.read('font.woff2'), [1, 2, 3]);
      await expectLater(
        ZipArchive.open(
          MemoryAsset(
            _zip(<_Member>[
              _Member('secret.bin', const [1], flags: 1),
            ]),
          ),
        ),
        throwsA(isA<ArchiveException>()),
        reason: 'encryption remains unsupported',
      );
    });

    test('rejects malformed input and configured index limits', () async {
      expect(
        ZipArchive.open(MemoryAsset(<int>[1, 2, 3])),
        throwsA(isA<ArchiveException>()),
      );
      final bytes = _zip(<_Member>[
        _Member('a.txt', <int>[1]),
        _Member('b.txt', <int>[2]),
      ]);
      expect(
        ZipArchive.open(MemoryAsset(bytes), limits: const ArchiveLimits(maxEntries: 1)),
        throwsA(isA<ArchiveException>()),
      );
      expect(
        ZipArchive.open(
          MemoryAsset(bytes),
          limits: const ArchiveLimits(maxArchiveSize: 22),
        ),
        throwsA(isA<ArchiveException>()),
      );
    });
  });

  group('ArchiveFetcher', () {
    test('does not mistake a filename without an extension for a media type', () async {
      final fetcher = ArchiveFetcher(
        await ZipArchive.open(
          MemoryAsset(
            _zip([
              _Member('xhtml', [1]),
              _Member('folder.css/file', [2]),
            ]),
          ),
        ),
      );
      addTearDown(fetcher.close);
      expect((await fetcher.open(Uri.parse('xhtml'))).mediaType, isNull);
      expect((await fetcher.open(Uri.parse('folder.css/file'))).mediaType, isNull);
    });

    test('preserves URI identity, reports media type, and closes ownership', () async {
      final fetcher = ArchiveFetcher(
        await ZipArchive.open(
          MemoryAsset(
            _zip(<_Member>[_Member('OPS/chapter.xhtml', utf8.encode('<p>Hi</p>'))]),
          ),
        ),
      );
      final resource = await fetcher.open(Uri.parse('OPS/chapter.xhtml?q=1#x'));
      expect(resource.href.toString(), 'OPS/chapter.xhtml?q=1#x');
      expect(resource.mediaType, 'application/xhtml+xml');
      expect(await resource.length, 9);
      expect(await fetcher.get(Uri.parse('missing.xhtml')), isNull);
      await fetcher.close();
      await fetcher.close();
      expect(
        () => fetcher.open(Uri.parse('OPS/chapter.xhtml')),
        throwsA(isA<ResourceException>()),
      );
    });
  });
}

final class _Member {
  const _Member(this.name, this.data, {this.deflate = false, this.flags = 0});
  final String name;
  final List<int> data;
  final bool deflate;
  final int flags;
}

Uint8List _zip(List<_Member> members) {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  for (final member in members) {
    final name = utf8.encode(member.name);
    final content = member.deflate
        ? ZLibEncoder(raw: true).convert(member.data)
        : member.data;
    final offset = out.length;
    _u32(out, 0x04034b50);
    _u16(out, 20);
    _u16(out, member.flags);
    _u16(out, member.deflate ? 8 : 0);
    _u16(out, 0);
    _u16(out, 0);
    _u32(out, _crc32(member.data));
    _u32(out, content.length);
    _u32(out, member.data.length);
    _u16(out, name.length);
    _u16(out, 0);
    out.add(name);
    out.add(content);
    _u32(central, 0x02014b50);
    _u16(central, 20);
    _u16(central, 20);
    _u16(central, member.flags);
    _u16(central, member.deflate ? 8 : 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, _crc32(member.data));
    _u32(central, content.length);
    _u32(central, member.data.length);
    _u16(central, name.length);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, 0);
    _u32(central, offset);
    central.add(name);
  }
  final centralBytes = central.toBytes();
  final offset = out.length;
  out.add(centralBytes);
  _u32(out, 0x06054b50);
  _u16(out, 0);
  _u16(out, 0);
  _u16(out, members.length);
  _u16(out, members.length);
  _u32(out, centralBytes.length);
  _u32(out, offset);
  _u16(out, 0);
  return out.toBytes();
}

void _u16(BytesBuilder out, int value) => out.add(<int>[value & 255, value >> 8 & 255]);
void _u32(BytesBuilder out, int value) =>
    out.add(<int>[value & 255, value >> 8 & 255, value >> 16 & 255, value >> 24 & 255]);
int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = crc & 1 == 0 ? crc >> 1 : crc >> 1 ^ 0xedb88320;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

/// Records the ranges requested from an in-memory asset.
final class _RecordingAsset implements Asset {
  _RecordingAsset(List<int> bytes, this.reads) : _source = MemoryAsset(bytes);

  final MemoryAsset _source;
  final List<(int?, int?)> reads;

  @override
  String? get name => null;

  @override
  Future<int?> get length => _source.length;

  @override
  Future<Uint8List> read({int? start, int? end}) {
    reads.add((start, end));
    return _source.read(start: start, end: end);
  }
}
