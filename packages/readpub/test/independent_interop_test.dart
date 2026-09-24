import 'dart:convert';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

void main() {
  test(
    'reads stored and Deflate data descriptors from Python streaming writer',
    () async {
      final archive = await ZipArchive.open(
        FileAsset('test/fixtures/independent-descriptors.zip'),
      );
      addTearDown(archive.close);
      expect(utf8.decode(await archive.read('stored.txt')), 'stored descriptor');
      expect(utf8.decode(await archive.read('deflate.txt')), 'deflate descriptor');
    },
  );

  test('reads independent Python ZIP with encoded and Unicode names', () async {
    final archive = await ZipArchive.open(
      FileAsset('test/fixtures/independent-python.zip'),
    );
    final fetcher = ArchiveFetcher(archive);
    addTearDown(fetcher.close);

    expect(archive.entries.length, 4);
    expect(utf8.decode(await archive.read('mimetype')), 'application/epub+zip');
    final chapter = await fetcher.open(
      Uri.parse('Text/chapter%20one.xhtml?edition=1#p1'),
    );
    expect(utf8.decode(await chapter.read()), '<p>Café &amp; tea.</p>');
    final literal = await fetcher.open(Uri.parse('literal%2520.txt'));
    expect(utf8.decode(await literal.read()), 'literal percent');
    final unicode = await fetcher.open(Uri.parse('Unicode/日本語.txt'));
    expect(utf8.decode(await unicode.read()), '言葉');
    expect(await fetcher.get(Uri.parse('literal%20.txt')), isNull);
  });
}
