import 'dart:convert';
import 'dart:io';

import 'package:readpub/readpub.dart';

/// Serves an EPUB and writes Dart-computed CFI samples for checking
/// `readerLocationScript` in a browser. Stop with Ctrl+C.
///
/// Usage: `dart run tool/location_script_samples.dart book.epub out.json [stride]`
/// Set `READPUB_PAGED=1` to serve chapters in the paged flow.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 || arguments.length > 3) {
    stderr.writeln(
      'Usage: dart run tool/location_script_samples.dart <book.epub> <out.json> [stride]',
    );
    exitCode = 64;
    return;
  }
  final stride = arguments.length == 3 ? int.parse(arguments[2]) : 13;
  final book = await EpubPublication.open(FileAsset(arguments[0]));
  final paged = Platform.environment['READPUB_PAGED'] == '1';
  final session = await EpubRenderSession.start(
    book,
    settings: ReaderSettings(flow: paged ? ReaderFlow.paged : ReaderFlow.scroll),
  );
  final services = ReadingServices(book);
  // Compares text without whitespace, which browsers and the text model
  // represent differently.
  String compact(String text, int count) {
    final visible = text.replaceAll(RegExp(r'\s'), '');
    return visible.length <= count ? visible : visible.substring(0, count);
  }

  final chapters = <Map<String, Object?>>[];
  for (final link in book.readingOrder) {
    final DocumentText? document;
    try {
      document = await services.documentText(link);
    } on ContentException {
      continue;
    }
    if (document == null || document.length == 0) continue;
    final points = <Map<String, String>>[];
    final ranges = <Map<String, String>>[];
    for (var offset = 0; offset < document.length; offset += stride) {
      points.add({
        'cfi': document.cfiAt(offset).expression,
        'text': compact(document.text.substring(offset), 10),
      });
      final end = (offset + 9).clamp(0, document.length);
      ranges.add({
        'cfi': document.cfiForRange(offset, end).expression,
        'text': compact(document.text.substring(offset, end), 9),
      });
    }
    chapters.add({
      'url': session.urlFor(link).toString(),
      'points': points,
      'ranges': ranges,
    });
  }
  await File(arguments[1]).writeAsString(jsonEncode(chapters));
  stdout.writeln('Wrote ${chapters.length} chapters to ${arguments[1]}');
  stdout.writeln('Serving ${session.indexUrl}');
  await ProcessSignal.sigint.watch().first;
  await session.close();
  await book.close();
}
