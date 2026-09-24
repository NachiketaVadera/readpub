import 'dart:io';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

void main() {
  test('defines the documented browser API without side effects on load', () {
    for (final name in [
      'cfiFromPoint',
      'cfiFromRange',
      'selectionCfi',
      'rangeFromCfi',
      'firstVisibleCfi',
      'scrollToCfi',
      'progression',
      'scrollToProgression',
    ]) {
      expect(readerLocationScript, contains('function $name('));
    }
    expect(readerLocationScript, contains('if (window.readpub) return;'));
    expect(readerLocationScript, isNot(contains('fetch(')));
    expect(readerLocationScript, isNot(contains('XMLHttpRequest')));
  });

  test('is syntactically valid JavaScript', () async {
    final directory = await Directory.systemTemp.createTemp('readpub-script');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/location.js');
    await file.writeAsString(readerLocationScript);
    final result = await Process.run('node', ['--check', file.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }, skip: _hasNode() ? false : 'Node.js is not installed');
}

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
