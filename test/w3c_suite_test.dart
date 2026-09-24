import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/conformance_checks.dart';

/// Runs the vendored W3C EPUB 3 tests (see test/fixtures/w3c/NOTICE.md).
void main() {
  final directory = Directory('test/fixtures/w3c');
  final manifest = jsonDecode(
    File('${directory.path}/manifest.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final tests = (manifest['tests']! as List).cast<Map<String, Object?>>();
  final client = HttpClient();
  tearDownAll(() => client.close(force: true));

  test('vendored tests are pinned and each has an observable requirement', () {
    expect(manifest['commit'], '4cc654f941fbe297a07877e09280ec3c473f3ec6');
    expect(tests, hasLength(35));
    for (final entry in tests) {
      final id = entry['id']! as String;
      expect(
        File('${directory.path}/${entry['file']}').existsSync(),
        isTrue,
        reason: id,
      );
      expect(
        conformanceChecks.containsKey(id) ||
            expectedContentErrors.contains(id) ||
            expectedOpenFailures.contains(id),
        isTrue,
        reason: '$id has nothing to assert',
      );
    }
  });

  for (final entry in tests) {
    final id = entry['id']! as String;
    test('$id: ${entry['description']}', () async {
      final result = await runConformanceTest(
        File('${directory.path}/${entry['file']}'),
        client,
      );
      final expected =
          expectedContentErrors.contains(id) || expectedOpenFailures.contains(id)
          ? ConformanceOutcome.expectedError
          : knownSuiteDefects.containsKey(id)
          ? ConformanceOutcome.suiteDefect
          : ConformanceOutcome.checked;
      expect(result.outcome, expected, reason: result.problems.join('\n'));
      if (conformanceChecks.containsKey(id)) expect(result.check, 'pass');
    });
  }
}
