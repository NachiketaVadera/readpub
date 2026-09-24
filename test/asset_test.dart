import 'dart:io';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryAsset', () {
    test('owns its input and reads half-open ranges', () async {
      final input = <int>[1, 2, 3, 4];
      final asset = MemoryAsset(input, name: 'book.epub');
      input[0] = 9;

      expect(asset.name, 'book.epub');
      expect(await asset.length, 4);
      expect(await asset.read(start: 1, end: 3), <int>[2, 3]);
      expect(await asset.read(start: 2, end: 2), isEmpty);
      expect(await asset.read(), <int>[1, 2, 3, 4]);
    });

    test('rejects invalid ranges', () async {
      final asset = MemoryAsset(<int>[1, 2]);
      expect(asset.read(start: -1), throwsA(isA<AssetException>()));
      expect(asset.read(start: 2, end: 1), throwsA(isA<AssetException>()));
      expect(asset.read(end: 3), throwsA(isA<AssetException>()));
    });
  });

  test('FileAsset reads an exact half-open range', () async {
    final file = await Directory.systemTemp.createTemp('readpub-asset-');
    addTearDown(() => file.delete(recursive: true));
    final path = '${file.path}${Platform.pathSeparator}book.epub';
    await File(path).writeAsBytes(<int>[10, 20, 30, 40]);
    final asset = FileAsset(path);

    expect(asset.name, 'book.epub');
    expect(await asset.length, 4);
    expect(await asset.read(start: 1, end: 4), <int>[20, 30, 40]);
  });
}
