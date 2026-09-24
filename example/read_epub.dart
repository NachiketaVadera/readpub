import 'dart:io';

import 'package:readpub/readpub.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/read_epub.dart <book.epub>');
    exitCode = 64;
    return;
  }
  try {
    final book = await EpubPublication.open(FileAsset(arguments.single));
    try {
      stdout.writeln(book.metadata.title);
      stdout.writeln('Authors: ${book.metadata.authors.map((a) => a.name).join(', ')}');
      stdout.writeln(
        'Layout: ${book.metadata.layout}; progression: ${book.metadata.readingProgression}',
      );
      for (final link in book.readingOrder) {
        stdout.writeln('${link.href} (${link.type})');
      }
      void printNavigation(List<Link> links, [String indent = '']) {
        for (final link in links) {
          stdout.writeln('$indent${link.title}: ${link.href}');
          printNavigation(link.children, '$indent  ');
        }
      }

      printNavigation(book.tableOfContents);
      final text = await book.resource(book.readingOrder.first).readAsString();
      stdout.writeln('First resource: ${text.length} characters');
      for (final warning in book.warnings) {
        stderr.writeln('${warning.code}: ${warning.message}');
      }
    } finally {
      await book.close();
    }
  } on PublicationException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  }
}
