import 'package:readpub/readpub.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: dart run example/read_archive.dart <book.epub>');
  }

  final archive = await ZipArchive.open(FileAsset(arguments.single));
  final fetcher = ArchiveFetcher(archive);
  try {
    for (final entry in archive.entries) {
      print('${entry.path} (${entry.size} bytes)');
    }
    final mimetype = await fetcher.open(Uri.parse('mimetype'));
    print(String.fromCharCodes(await mimetype.read()));
  } finally {
    await fetcher.close();
  }
}
