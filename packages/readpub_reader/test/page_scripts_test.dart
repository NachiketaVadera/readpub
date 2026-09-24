import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:readpub_reader/readpub_reader.dart';

void main() {
  final scripts = {
    'bridge': readerBridgeScript,
    'decorations': readerDecorationScript,
  };

  test('define their APIs once and make no network requests', () {
    expect(readerBridgeScript, contains('if (window.readpubReader'));
    expect(readerDecorationScript, contains('if (window.readpubDecorations'));
    for (final script in scripts.values) {
      expect(script, contains(readerChannelName));
      expect(script, isNot(contains('fetch(')));
      expect(script, isNot(contains('XMLHttpRequest')));
    }
  });

  test('are syntactically valid JavaScript', () async {
    final directory = await Directory.systemTemp.createTemp('readpub-reader');
    addTearDown(() => directory.delete(recursive: true));
    for (final MapEntry(key: name, value: script) in scripts.entries) {
      final file = File('${directory.path}/$name.js');
      await file.writeAsString(script);
      final result = await Process.run('node', ['--check', file.path]);
      expect(result.exitCode, 0, reason: '$name: ${result.stderr}');
    }
  }, skip: _hasNode() ? false : 'Node.js is not installed');
}

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
