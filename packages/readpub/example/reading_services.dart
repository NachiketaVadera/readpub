import 'dart:convert';
import 'dart:io';

import 'package:readpub/readpub.dart';

/// Prints positions, search results and a restored locator for an EPUB.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Usage: dart run example/reading_services.dart <book.epub> <query>');
    exitCode = 64;
    return;
  }
  EpubPublication? book;
  try {
    book = await EpubPublication.open(FileAsset(arguments[0]));
    final services = ReadingServices(book);
    final positions = await services.positions();
    stdout.writeln('${book.metadata.title}: ${positions.total} positions');
    for (final href in positions.unreadable) {
      stderr.writeln('Unreadable document given one position: $href');
    }

    await for (final result in services.search(arguments[1])) {
      final locator = result.locator;
      stdout.writeln(
        '[${locator.locations.position}] ${locator.title ?? locator.href}: '
        '…${locator.text.before}[${locator.text.highlight}]${locator.text.after}…',
      );
      stdout.writeln('  ${result.cfi}');
    }

    // Save a reading location as JSON, then restore it.
    final middle = positions.locators[positions.total ~/ 2];
    final saved = jsonEncode(middle.toJson());
    final restored = await services.resolve(Locator.fromJson(jsonDecode(saved)));
    stdout.writeln(
      'Restored position ${middle.locations.position} by ${restored?.match.name}: '
      '${restored?.cfi}',
    );
  } on PublicationException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } finally {
    await book?.close();
  }
}
