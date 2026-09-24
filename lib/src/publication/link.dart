part of 'model.dart';

/// A resource reference or a node in a publication navigation tree.
final class Link extends _ValueModel {
  /// Creates an immutable link.
  Link({
    required this.href,
    this.type,
    this.title,
    this.duration,
    Iterable<String> rels = const [],
    Map<String, String> properties = const {},
    Iterable<Link> children = const [],
    Iterable<Link> alternates = const [],
  }) : rels = Set.unmodifiable(rels),
       properties = Map.unmodifiable(properties),
       children = List.unmodifiable(children),
       alternates = List.unmodifiable(alternates);

  /// The encoded URI, or an empty string for a navigation group without a target.
  final String href;

  /// The normalized media type, when known.
  final String? type;

  /// The display label.
  final String? title;

  /// The declared media duration, when available.
  final Duration? duration;

  /// The resource relations.
  final Set<String> rels;

  /// The normalized resource properties and retained format extensions.
  final Map<String, String> properties;

  /// The nested navigation nodes.
  final List<Link> children;

  /// The fallback or media-overlay resources.
  final List<Link> alternates;
  @override
  Map<String, Object?> toJson() => {
    'href': href,
    if (type != null) 'type': type,
    if (title != null) 'title': title,
    if (duration != null) 'duration': duration!.inMicroseconds / 1000000,
    'rel': rels.toList()..sort(),
    'properties': properties,
    'children': children.map((v) => v.toJson()).toList(),
    'alternate': alternates.map((v) => v.toJson()).toList(),
  };
}

/// A role-based publication collection with nested collections and metadata.
final class PublicationCollection extends _ValueModel {
  /// Creates an immutable collection.
  PublicationCollection({
    required this.role,
    Iterable<Link> links = const [],
    Iterable<PublicationCollection> children = const [],
    Iterable<MetadataRecord> metadata = const [],
  }) : links = List.unmodifiable(links),
       children = List.unmodifiable(children),
       metadata = List.unmodifiable(metadata);

  /// The collection role.
  final String role;

  /// The collection resources.
  final List<Link> links;

  /// The nested collections.
  final List<PublicationCollection> children;

  /// The source metadata declared for this collection.
  final List<MetadataRecord> metadata;
  @override
  Map<String, Object?> toJson() => {
    'role': role,
    'links': links.map((v) => v.toJson()).toList(),
    'children': children.map((v) => v.toJson()).toList(),
    'metadata': metadata.map((v) => v.toJson()).toList(),
  };
}
