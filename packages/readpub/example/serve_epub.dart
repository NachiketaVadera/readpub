import 'dart:io';

import 'package:readpub/readpub.dart';

/// Serves an EPUB to a local browser until interrupted with Ctrl+C.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/serve_epub.dart <book.epub>');
    exitCode = 64;
    return;
  }
  EpubPublication? book;
  EpubRenderSession? session;
  try {
    book = await EpubPublication.open(FileAsset(arguments.single));
    session = await EpubRenderSession.start(book);
    stdout.writeln('Open ${session.indexUrl} in a browser or WebView.');
    stdout.writeln('Press Ctrl+C to stop.');
    await ProcessSignal.sigint.watch().first;
  } on PublicationException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } finally {
    await session?.close();
    await book?.close();
  }
}
