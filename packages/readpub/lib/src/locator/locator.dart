import 'package:collection/collection.dart';

const _equality = DeepCollectionEquality();
const _reservedLocationKeys = {
  'fragments',
  'progression',
  'position',
  'totalProgression',
};

/// A precise, persistable location in a publication resource.
///
/// A locator combines several independent location representations: resource
/// progression, fragment identifiers, a publication position, extension
/// locations such as a content-document CFI, and surrounding text. Consumers
/// can restore a location from whichever representation is still valid after
/// a publication or renderer changes.
///
/// The JSON form uses the field names of the Readium Locator model. It has no
/// version field: later releases may add optional fields, readers ignore
/// unknown top-level fields and preserve unknown `locations` fields, and the
/// meaning of existing fields changes only in a major release. Store the
/// publication identifier alongside a locator; a locator alone does not
/// identify its publication.
final class Locator {
  /// Creates a validated locator.
  ///
  /// [href] is a non-empty, publication-relative encoded URI without a
  /// fragment; fragment identifiers belong in [Locations.fragments]. [type] is
  /// the resource media type.
  Locator({
    required this.href,
    required this.type,
    this.title,
    Locations? locations,
    LocatorText? text,
  }) : locations = locations ?? Locations(),
       text = text ?? const LocatorText() {
    if (href.isEmpty || href.contains('#')) {
      throw ArgumentError.value(href, 'href', 'Must be non-empty and fragment-free.');
    }
    if (!_mediaType.hasMatch(type)) {
      throw ArgumentError.value(type, 'type', 'Must be a media type.');
    }
  }

  /// Decodes a locator from JSON-compatible data, such as `jsonDecode` output.
  ///
  /// Throws a [FormatException] when a known field has an invalid value.
  factory Locator.fromJson(Object? json) {
    final map = _object(json, 'locator');
    final href = map['href'];
    final type = map['type'];
    final title = map['title'];
    if (href is! String || type is! String || (title != null && title is! String)) {
      throw const FormatException('Locator requires string href and type values.');
    }
    return _guard(
      () => Locator(
        href: href,
        type: type,
        title: title as String?,
        locations: map['locations'] == null
            ? null
            : Locations.fromJson(map['locations']),
        text: map['text'] == null ? null : LocatorText.fromJson(map['text']),
      ),
    );
  }

  /// The publication-relative encoded resource URI, without a fragment.
  final String href;

  /// The resource media type.
  final String type;

  /// A human-readable title for the location, such as its chapter title.
  final String? title;

  /// The location within the resource.
  final Locations locations;

  /// The text surrounding or selected at the location.
  final LocatorText text;

  /// Returns a copy with the given non-null values replaced.
  Locator copyWith({
    String? href,
    String? type,
    String? title,
    Locations? locations,
    LocatorText? text,
  }) => Locator(
    href: href ?? this.href,
    type: type ?? this.type,
    title: title ?? this.title,
    locations: locations ?? this.locations,
    text: text ?? this.text,
  );

  /// Serializes this locator, omitting absent and empty values.
  Map<String, Object?> toJson() => {
    'href': href,
    'type': type,
    'title': ?title,
    if (!locations.isEmpty) 'locations': locations.toJson(),
    if (!text.isEmpty) 'text': text.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Locator && _equality.equals(toJson(), other.toJson());

  @override
  int get hashCode => _equality.hash(toJson());

  @override
  String toString() => 'Locator(${toJson()})';
}

/// Location representations within one publication resource.
final class Locations {
  /// Creates validated locations.
  ///
  /// [progression] and [totalProgression] must be finite values from 0 to 1.
  /// [position] is one-based. [otherLocations] holds JSON-compatible extension
  /// values, such as `partialCfi`, and is deeply copied.
  Locations({
    Iterable<String> fragments = const [],
    this.progression,
    this.position,
    this.totalProgression,
    Map<String, Object?> otherLocations = const {},
  }) : fragments = List.unmodifiable(fragments),
       otherLocations = Map.unmodifiable({
         for (final entry in otherLocations.entries)
           entry.key: _frozenJson(entry.value, entry.key),
       }) {
    if (this.fragments.any((fragment) => fragment.isEmpty)) {
      throw ArgumentError.value(
        fragments,
        'fragments',
        'Must not contain empty values.',
      );
    }
    _checkUnit(progression, 'progression');
    _checkUnit(totalProgression, 'totalProgression');
    if (position != null && position! < 1) {
      throw ArgumentError.value(position, 'position', 'Must be one-based.');
    }
    final reserved = otherLocations.keys.where(_reservedLocationKeys.contains);
    if (reserved.isNotEmpty || otherLocations.keys.any((key) => key.isEmpty)) {
      throw ArgumentError.value(
        otherLocations.keys.toList(),
        'otherLocations',
        'Must not use empty or reserved keys.',
      );
    }
  }

  /// Decodes locations from JSON-compatible data.
  ///
  /// Unknown fields are retained in [otherLocations]. Throws a
  /// [FormatException] when a known field has an invalid value.
  factory Locations.fromJson(Object? json) {
    final map = _object(json, 'locations');
    final fragments = map['fragments'] ?? const <Object?>[];
    final progression = map['progression'];
    final position = map['position'];
    final totalProgression = map['totalProgression'];
    if (fragments is! List || fragments.any((value) => value is! String)) {
      throw const FormatException('Locator fragments must be a list of strings.');
    }
    if ((progression != null && progression is! num) ||
        (totalProgression != null && totalProgression is! num)) {
      throw const FormatException('Locator progression values must be numbers.');
    }
    final int? wholePosition = switch (position) {
      null => null,
      final int value => value,
      final double value when value.isFinite && value == value.truncateToDouble() =>
        value.toInt(),
      _ => throw const FormatException('Locator position must be an integer.'),
    };
    return _guard(
      () => Locations(
        fragments: fragments.cast<String>(),
        progression: (progression as num?)?.toDouble(),
        position: wholePosition,
        totalProgression: (totalProgression as num?)?.toDouble(),
        otherLocations: {
          for (final entry in map.entries)
            if (!_reservedLocationKeys.contains(entry.key)) entry.key: entry.value,
        },
      ),
    );
  }

  /// Fragment identifiers within the resource, such as element IDs.
  final List<String> fragments;

  /// The progression within the resource, from 0 to 1.
  final double? progression;

  /// The one-based publication position.
  final int? position;

  /// The progression within the whole publication, from 0 to 1.
  final double? totalProgression;

  /// Extension locations, keyed by their JSON field name.
  final Map<String, Object?> otherLocations;

  /// A content-document EPUB CFI point, without the `epubcfi()` wrapper.
  ///
  /// The expression is relative to the root element of the resource
  /// identified by [Locator.href], as in the Readium `partialCfi` extension.
  String? get partialCfi => switch (otherLocations['partialCfi']) {
    final String value => value,
    _ => null,
  };

  /// A CSS selector identifying the location's element, when supplied.
  String? get cssSelector => switch (otherLocations['cssSelector']) {
    final String value => value,
    _ => null,
  };

  /// Whether no location representation is present.
  bool get isEmpty =>
      fragments.isEmpty &&
      progression == null &&
      position == null &&
      totalProgression == null &&
      otherLocations.isEmpty;

  /// Returns a copy with the given non-null values replaced.
  Locations copyWith({
    Iterable<String>? fragments,
    double? progression,
    int? position,
    double? totalProgression,
    Map<String, Object?>? otherLocations,
  }) => Locations(
    fragments: fragments ?? this.fragments,
    progression: progression ?? this.progression,
    position: position ?? this.position,
    totalProgression: totalProgression ?? this.totalProgression,
    otherLocations: otherLocations ?? this.otherLocations,
  );

  /// Serializes these locations, omitting absent values.
  Map<String, Object?> toJson() => {
    if (fragments.isNotEmpty) 'fragments': fragments,
    'progression': ?progression,
    'position': ?position,
    'totalProgression': ?totalProgression,
    ...otherLocations,
  };

  @override
  bool operator ==(Object other) =>
      other is Locations && _equality.equals(toJson(), other.toJson());

  @override
  int get hashCode => _equality.hash(toJson());

  @override
  String toString() => 'Locations(${toJson()})';
}

/// Text surrounding, or highlighted at, a location.
///
/// A locator with [highlight] identifies a range: it starts at the location
/// and extends over the highlighted text.
final class LocatorText {
  /// Creates locator text.
  const LocatorText({this.before, this.highlight, this.after});

  /// Decodes locator text from JSON-compatible data.
  factory LocatorText.fromJson(Object? json) {
    final map = _object(json, 'text');
    String? value(String key) => switch (map[key]) {
      null => null,
      final String text => text,
      _ => throw FormatException('Locator text $key must be a string.'),
    };
    return LocatorText(
      before: value('before'),
      highlight: value('highlight'),
      after: value('after'),
    );
  }

  /// Text immediately preceding the location or highlight.
  final String? before;

  /// The text at the location, when it identifies a range.
  final String? highlight;

  /// Text immediately following the location or highlight.
  final String? after;

  /// Whether no text is present.
  bool get isEmpty => before == null && highlight == null && after == null;

  /// Serializes this text, omitting absent values.
  Map<String, Object?> toJson() => {
    'before': ?before,
    'highlight': ?highlight,
    'after': ?after,
  };

  @override
  bool operator ==(Object other) =>
      other is LocatorText &&
      other.before == before &&
      other.highlight == highlight &&
      other.after == after;

  @override
  int get hashCode => Object.hash(before, highlight, after);

  @override
  String toString() => 'LocatorText(${toJson()})';
}

final _mediaType = RegExp(r'^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$');

void _checkUnit(double? value, String name) {
  if (value != null && (!value.isFinite || value < 0 || value > 1)) {
    throw ArgumentError.value(value, name, 'Must be a finite value from 0 to 1.');
  }
}

Map<String, Object?> _object(Object? json, String name) {
  if (json is! Map || json.keys.any((key) => key is! String)) {
    throw FormatException('Locator $name must be a JSON object.');
  }
  return json.cast<String, Object?>();
}

T _guard<T>(T Function() build) {
  try {
    return build();
  } on ArgumentError catch (error) {
    throw FormatException('Invalid locator value: ${error.message}');
  }
}

Object? _frozenJson(Object? value, String path, [int depth = 0]) {
  if (depth > 64) {
    throw ArgumentError.value(path, 'otherLocations', 'Nesting is too deep.');
  }
  return switch (value) {
    null || bool() || String() => value,
    num() when value.isFinite => value,
    List() => List<Object?>.unmodifiable(
      value.map((item) => _frozenJson(item, path, depth + 1)),
    ),
    Map() when value.keys.every((key) => key is String) =>
      Map<String, Object?>.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: _frozenJson(entry.value, path, depth + 1),
      }),
    _ => throw ArgumentError.value(value, path, 'Must be JSON-compatible.'),
  };
}
