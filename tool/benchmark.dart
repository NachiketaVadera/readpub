import 'dart:io';

import 'package:readpub/readpub.dart';

/// Measures parsing, reading services, rendering and range reads.
///
/// Usage: `dart run tool/benchmark.dart book.epub`. Generate a large book
/// with `tool/generate_benchmark_epub.py`. Results depend on the machine and
/// are recorded with their environment in docs/PERFORMANCE.md.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/benchmark.dart <book.epub>');
    exitCode = 64;
    return;
  }
  final file = File(arguments.single);
  stdout.writeln(
    '${file.path}: ${(file.lengthSync() / 1048576).toStringAsFixed(1)} MB, '
    'Dart ${Platform.version.split(' ').first}, ${Platform.operatingSystem}',
  );
  final watch = Stopwatch()..start();
  void report(String phase, [String detail = '']) {
    final rss = (ProcessInfo.maxRss / 1048576).toStringAsFixed(0);
    stdout.writeln(
      '${phase.padRight(34)} ${watch.elapsedMilliseconds.toString().padLeft(7)} ms'
      '  peak RSS ${rss.padLeft(5)} MB  $detail',
    );
    watch.reset();
  }

  final book = await EpubPublication.open(FileAsset(file.path));
  int count(List<Link> links) =>
      links.fold(0, (total, link) => total + 1 + count(link.children));
  report(
    'open',
    '${book.readingOrder.length} spine, ${book.resources.length} resources, '
        '${count(book.tableOfContents)} TOC entries',
  );
  final services = ReadingServices(book);
  final first = await services.documentText(book.readingOrder.first);
  report('parse first chapter (cold)', '${first!.length} characters');
  final positions = await services.positions();
  var characters = 0;
  for (var i = 0; i < book.readingOrder.length; i++) {
    characters += positions.forReadingOrder(i).length;
  }
  report('positions (all chapters)', '${positions.total} positions');
  final cached = PublicationPositions.fromJson(positions.toJson());
  report('positions from JSON cache', '${cached.total} positions');

  var results = await services
      .search('harbor', options: const SearchOptions(maxResults: 1))
      .length;
  report('search first match', '$results result');
  results = await services
      .search('lantern voyage', options: const SearchOptions(maxResults: 100000))
      .length;
  report('search whole book, common phrase', '$results results');
  results = await services.search('xylophone').length;
  report('search whole book, no match', '$results results');

  const samples = 200;
  for (var i = 0; i < samples; i++) {
    final link = book.readingOrder[(i * 7919) % book.readingOrder.length];
    final locator = await services.locatorForProgression(link, (i % 10) / 10);
    final resolution = await services.resolve(locator);
    if (resolution?.match != LocatorMatch.cfi) {
      throw StateError('Locator did not resolve by CFI: $locator');
    }
  }
  report('locator create + resolve', '$samples round trips');

  final session = await EpubRenderSession.start(book);
  for (final link in book.readingOrder.take(20)) {
    await session.prepare(link);
  }
  report('render prepare', '20 chapters');
  await session.close();

  Future<void> ranges(String suffix, String label) async {
    final link = book.resources.firstWhere((link) => link.href.endsWith(suffix));
    final resource = book.resource(link);
    final length = (await resource.length)!;
    const reads = 20;
    for (var i = 0; i < reads; i++) {
      final start = ((length - 65536) ~/ reads) * i;
      await resource.read(start: start, end: start + 65536);
    }
    report(label, '$reads x 64 KiB of ${(length / 1048576).toStringAsFixed(1)} MB');
  }

  await ranges('.jpg', 'range reads, deflated image');
  await ranges('.mp3', 'range reads, stored audio');
  await book.close();
  stdout.writeln('${book.readingOrder.length} chapters, $characters positions total');
}
