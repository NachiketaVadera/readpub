part of 'reading_services.dart';

/// Per-resource position data.
final class _PositionResource {
  const _PositionResource(
    this.href,
    this.start,
    this.count,
    this.length,
    this.unreadable,
  );

  final String href;

  /// The first one-based position of the resource.
  final int start;
  final int count;

  /// The text length, or null for fixed-layout and non-text resources.
  final int? length;
  final bool unreadable;
}

/// Deterministic publication positions, independent of rendered pixels.
///
/// Every reading-order resource has at least one position. A reflowable text
/// resource has one position per [charactersPerPosition] UTF-16 code units of
/// normalized reading text, rounded up. Fixed-layout resources, resources
/// without text and non-text resources have exactly one position. Non-linear
/// resources are not part of the reading order and have no positions.
///
/// Positions are derived data. The JSON form is a cache: it records
/// [formatVersion] and [charactersPerPosition], and must be discarded when
/// either differs or the publication changes. Positions in persisted locators
/// are informational; restore locations from CFIs, text and progression.
final class PublicationPositions {
  PublicationPositions._(this.charactersPerPosition, this._resources, this.locators);

  /// Decodes cached positions, validating their internal consistency.
  ///
  /// Throws a [FormatException] for another format version or invalid data.
  factory PublicationPositions.fromJson(Object? json) {
    if (json is! Map ||
        json['version'] != formatVersion ||
        json['charactersPerPosition'] is! int ||
        json['resources'] is! List ||
        json['positions'] is! List) {
      throw const FormatException('Unsupported publication positions cache.');
    }
    final perPosition = json['charactersPerPosition'] as int;
    final resources = <_PositionResource>[];
    var start = 1;
    for (final item in json['resources'] as List) {
      if (item is! Map ||
          item['href'] is! String ||
          item['count'] is! int ||
          (item['length'] != null && item['length'] is! int) ||
          (item['count'] as int) < 1) {
        throw const FormatException('Invalid publication positions resource.');
      }
      resources.add(
        _PositionResource(
          item['href'] as String,
          start,
          item['count'] as int,
          item['length'] as int?,
          item['unreadable'] == true,
        ),
      );
      start += item['count'] as int;
    }
    final locators = [
      for (final item in json['positions'] as List) Locator.fromJson(item),
    ];
    if (perPosition < 1 || locators.length != start - 1) {
      throw const FormatException('Publication positions are inconsistent.');
    }
    for (final resource in resources) {
      for (var k = 0; k < resource.count; k++) {
        final locator = locators[resource.start - 1 + k];
        if (locator.href != resource.href ||
            locator.locations.position != resource.start + k) {
          throw const FormatException('Publication positions are inconsistent.');
        }
      }
    }
    return PublicationPositions._(
      perPosition,
      List.unmodifiable(resources),
      List.unmodifiable(locators),
    );
  }

  /// The version of the position algorithm and cache format.
  static const formatVersion = 1;

  /// The number of text code units per reflowable position.
  final int charactersPerPosition;

  final List<_PositionResource> _resources;

  /// Every position, in order; `locators[i]` has position `i + 1`.
  final List<Locator> locators;

  /// The total number of positions.
  int get total => locators.length;

  /// The hrefs of reading-order resources that could not be parsed and were
  /// given a single position.
  List<String> get unreadable => List.unmodifiable([
    for (final resource in _resources)
      if (resource.unreadable) resource.href,
  ]);

  /// The positions of the reading-order resource at [readingOrderIndex].
  List<Locator> forReadingOrder(int readingOrderIndex) {
    final resource = _resources[readingOrderIndex];
    return locators.sublist(resource.start - 1, resource.start - 1 + resource.count);
  }

  /// The one-based position containing [progression] within a resource.
  int positionAt(int readingOrderIndex, double progression) {
    final resource = _resources[readingOrderIndex];
    final length = resource.length;
    if (length == null || length == 0) return resource.start;
    final offset = (progression.clamp(0, 1) * length).round();
    return resource.start + min(resource.count - 1, offset ~/ charactersPerPosition);
  }

  /// The publication progression corresponding to [progression] within a
  /// reading-order resource.
  double totalProgressionAt(int readingOrderIndex, double progression) {
    final resource = _resources[readingOrderIndex];
    final length = resource.length;
    final value = progression.clamp(0, 1).toDouble();
    final fraction = length == null || length == 0
        ? value * resource.count
        : min(resource.count.toDouble(), value * length / charactersPerPosition);
    return ((resource.start - 1 + fraction) / total).clamp(0, 1).toDouble();
  }

  (int, double) _atOffset(int readingOrderIndex, int offset, int length) {
    final resource = _resources[readingOrderIndex];
    final known = resource.length;
    if (known == null || known == 0 || length == 0) {
      final fraction = length == 0 ? 0.0 : offset / length;
      return (
        resource.start,
        ((resource.start - 1 + fraction) / total).clamp(0, 1).toDouble(),
      );
    }
    final int position =
        resource.start + min(resource.count - 1, offset ~/ charactersPerPosition);
    final fraction = min(resource.count.toDouble(), offset / charactersPerPosition);
    return (position, ((resource.start - 1 + fraction) / total).clamp(0, 1).toDouble());
  }

  bool _matches(List<Link> readingOrder, int perPosition) =>
      perPosition == charactersPerPosition &&
      readingOrder.length == _resources.length &&
      [
        for (var i = 0; i < readingOrder.length; i++)
          readingOrder[i].href == _resources[i].href,
      ].every((same) => same);

  /// Serializes these positions as a cache entry.
  Map<String, Object?> toJson() => {
    'version': formatVersion,
    'charactersPerPosition': charactersPerPosition,
    'resources': [
      for (final resource in _resources)
        {
          'href': resource.href,
          'count': resource.count,
          'length': ?resource.length,
          if (resource.unreadable) 'unreadable': true,
        },
    ],
    'positions': [for (final locator in locators) locator.toJson()],
  };
}
