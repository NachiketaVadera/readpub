import 'dart:convert';
import 'dart:io';

import 'conformance_checks.dart';

/// Runs every EPUB in a directory through parsing, resource access, text
/// extraction, render preparation and positions, checks the requirements of
/// known W3C EPUB tests that this library can observe, and writes a JSON
/// report. See `conformance_checks.dart` for the outcome categories.
///
/// The complete W3C test suite is not included in this repository; build it
/// with the suite's `generateEpubs.sh`. Selected tests are vendored in
/// `test/fixtures/w3c`.
///
/// Usage: `dart run tool/conformance.dart tests-dir report.json`
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Usage: dart run tool/conformance.dart <epub-dir> <report.json>');
    exitCode = 64;
    return;
  }
  final files =
      Directory(arguments[0])
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.epub'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final client = HttpClient();
  final results = <ConformanceResult>[];
  try {
    for (final file in files) {
      results.add(await runConformanceTest(file, client));
    }
  } finally {
    client.close(force: true);
  }
  final outcomes = <String, int>{};
  for (final result in results) {
    outcomes.update(result.outcome.label, (count) => count + 1, ifAbsent: () => 1);
  }
  await File(arguments[1]).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'total': results.length,
      'outcomes': outcomes,
      'results': [for (final result in results) result.toJson()],
    }),
  );
  stdout.writeln('${results.length} publications: $outcomes');
  for (final result in results) {
    if (result.outcome == ConformanceOutcome.problem) {
      stdout.writeln('${result.id}: ${result.problems.join(' | ')}');
    }
  }
}
