import 'dart:convert';

import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

void main() {
  final complete = Locator(
    href: 'OEBPS/Text/chapter%20one.xhtml',
    type: 'application/xhtml+xml',
    title: 'Chapter One',
    locations: Locations(
      fragments: ['start'],
      progression: 0.25,
      position: 3,
      totalProgression: 0.125,
      otherLocations: {
        'partialCfi': '/4/2/1:3',
        'x-app': {
          'nested': [1, true, null],
        },
      },
    ),
    text: const LocatorText(before: 'Once ', highlight: 'upon', after: ' a time'),
  );

  test('round-trips through JSON text', () {
    final decoded = Locator.fromJson(jsonDecode(jsonEncode(complete)));
    expect(decoded, complete);
    expect(decoded.hashCode, complete.hashCode);
    expect(decoded.locations.partialCfi, '/4/2/1:3');
    expect(decoded.locations.cssSelector, isNull);
    expect(decoded.toJson(), {
      'href': 'OEBPS/Text/chapter%20one.xhtml',
      'type': 'application/xhtml+xml',
      'title': 'Chapter One',
      'locations': {
        'fragments': ['start'],
        'progression': 0.25,
        'position': 3,
        'totalProgression': 0.125,
        'partialCfi': '/4/2/1:3',
        'x-app': {
          'nested': [1, true, null],
        },
      },
      'text': {'before': 'Once ', 'highlight': 'upon', 'after': ' a time'},
    });
  });

  test('omits empty values and accepts integral JSON numbers', () {
    final minimal = Locator(href: 'a.xhtml', type: 'application/xhtml+xml');
    expect(minimal.toJson(), {'href': 'a.xhtml', 'type': 'application/xhtml+xml'});
    final decoded = Locator.fromJson({
      'href': 'a.xhtml',
      'type': 'application/xhtml+xml',
      'locations': {'progression': 1, 'position': 2.0, 'totalProgression': 0},
      'future': 'ignored',
    });
    expect(decoded.locations.progression, 1.0);
    expect(decoded.locations.position, 2);
    expect(decoded.locations.totalProgression, 0.0);
    expect(decoded.toJson().containsKey('future'), isFalse);
  });

  test('keeps extension values deeply immutable', () {
    final source = <String, Object?>{
      'custom': [1, 2],
    };
    final locations = Locations(otherLocations: source);
    (source['custom']! as List).add(3);
    expect(locations.otherLocations['custom'], [1, 2]);
    expect(
      () => (locations.otherLocations['custom']! as List).add(4),
      throwsUnsupportedError,
    );
    expect(() => locations.fragments.add('x'), throwsUnsupportedError);
  });

  test('copies with replacements', () {
    final moved = complete.copyWith(
      locations: complete.locations.copyWith(progression: 0.5),
    );
    expect(moved.locations.progression, 0.5);
    expect(moved.locations.position, 3);
    expect(moved.title, 'Chapter One');
    expect(moved, isNot(complete));
  });

  test('validates constructor values', () {
    Locator make(String href, String type) => Locator(href: href, type: type);
    expect(() => make('', 'text/html'), throwsArgumentError);
    expect(() => make('a.xhtml#x', 'text/html'), throwsArgumentError);
    expect(() => make('a.xhtml', 'html'), throwsArgumentError);
    expect(() => Locations(progression: 1.5), throwsArgumentError);
    expect(() => Locations(totalProgression: double.nan), throwsArgumentError);
    expect(() => Locations(position: 0), throwsArgumentError);
    expect(() => Locations(fragments: ['']), throwsArgumentError);
    expect(() => Locations(otherLocations: {'position': 1}), throwsArgumentError);
    expect(() => Locations(otherLocations: {'x': Object()}), throwsArgumentError);
    expect(
      () => Locations(otherLocations: {'x': double.infinity}),
      throwsArgumentError,
    );
  });

  for (final invalid in <Object?>[
    null,
    [],
    {'href': 'a.xhtml'},
    {'href': 1, 'type': 'text/html'},
    {'href': 'a.xhtml#f', 'type': 'text/html'},
    {
      'href': 'a.xhtml',
      'type': 'text/html',
      'locations': {'progression': '0.5'},
    },
    {
      'href': 'a.xhtml',
      'type': 'text/html',
      'locations': {'position': 1.5},
    },
    {
      'href': 'a.xhtml',
      'type': 'text/html',
      'locations': {'progression': 2},
    },
    {
      'href': 'a.xhtml',
      'type': 'text/html',
      'locations': {
        'fragments': [1],
      },
    },
    {
      'href': 'a.xhtml',
      'type': 'text/html',
      'text': {'highlight': 3},
    },
    {'href': 'a.xhtml', 'type': 'text/html', 'title': 7},
  ]) {
    test('rejects invalid JSON $invalid', () {
      expect(() => Locator.fromJson(invalid), throwsFormatException);
    });
  }
}
