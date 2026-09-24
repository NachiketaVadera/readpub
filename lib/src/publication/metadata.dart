part of 'model.dart';

/// Immutable, format-independent publication metadata.
final class Metadata extends _ValueModel {
  /// Creates normalized metadata with defensive collection copies.
  Metadata({
    required this.title,
    this.subtitle,
    this.identifier,
    this.description,
    this.rights,
    this.published,
    this.modified,
    this.duration,
    this.numberOfPages,
    this.readingProgression = 'auto',
    this.layout = 'reflowable',
    this.orientation,
    this.spread,
    this.cover,
    Iterable<LocalizedString> titles = const [],
    Iterable<Contributor> authors = const [],
    Iterable<Contributor> contributors = const [],
    Iterable<Contributor> publishers = const [],
    Iterable<Subject> subjects = const [],
    Iterable<String> languages = const [],
    Iterable<String> identifiers = const [],
    Iterable<MetadataRecord> raw = const [],
    Iterable<CollectionMembership> belongsTo = const [],
    Map<String, String> properties = const {},
    Map<String, String> prefixes = const {},
    Map<String, List<String>> accessibility = const {},
  }) : titles = List.unmodifiable(titles),
       authors = List.unmodifiable(authors),
       contributors = List.unmodifiable(contributors),
       publishers = List.unmodifiable(publishers),
       subjects = List.unmodifiable(subjects),
       languages = List.unmodifiable(languages),
       identifiers = List.unmodifiable(identifiers),
       raw = List.unmodifiable(raw),
       belongsTo = List.unmodifiable(belongsTo),
       properties = Map.unmodifiable(properties),
       prefixes = Map.unmodifiable(prefixes),
       accessibility = Map.unmodifiable({
         for (final item in accessibility.entries)
           item.key: List<String>.unmodifiable(item.value),
       });

  /// The primary display title.
  final String title;

  /// The primary subtitle, if supplied.
  final String? subtitle;

  /// All declared title strings.
  final List<LocalizedString> titles;

  /// The publication's designated identifier.
  final String? identifier;

  /// All declared identifiers.
  final List<String> identifiers;

  /// The declared languages.
  final List<String> languages;

  /// The publication authors.
  final List<Contributor> authors;

  /// Contributors other than normalized authors and publishers.
  final List<Contributor> contributors;

  /// The publication publishers.
  final List<Contributor> publishers;

  /// Editors identified by their MARC role.
  List<Contributor> get editors =>
      List.unmodifiable(contributors.where((c) => c.roles.contains('edt')));

  /// Translators identified by their MARC role.
  List<Contributor> get translators =>
      List.unmodifiable(contributors.where((c) => c.roles.contains('trl')));

  /// The publication subjects.
  final List<Subject> subjects;

  /// The publication description.
  final String? description;

  /// The rights statement.
  final String? rights;

  /// The publication date; partial source dates use the first day of the period.
  final DateTime? published;

  /// The last modification date.
  final DateTime? modified;

  /// The declared total media duration.
  final Duration? duration;

  /// The declared page count, when available.
  final int? numberOfPages;

  /// The progression direction: `auto`, `ltr`, `rtl`, `ttb`, or `btt`.
  final String readingProgression;

  /// The layout: `reflowable` or `fixed`.
  final String layout;

  /// The preferred orientation, when declared.
  final String? orientation;

  /// The preferred synthetic-spread behavior, when declared.
  final String? spread;

  /// The declared cover resource.
  final Link? cover;

  /// Accessibility vocabulary values, retaining repeated properties.
  final Map<String, List<String>> accessibility;

  /// Collection or series memberships.
  final List<CollectionMembership> belongsTo;

  /// Source vocabulary prefix declarations.
  final Map<String, String> prefixes;

  /// Unrefined package properties, with the first repeated value retained.
  final Map<String, String> properties;

  /// Complete source metadata records, including unknown and refined values.
  final List<MetadataRecord> raw;
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (identifier != null) 'identifier': identifier,
    'titles': titles.map((v) => v.toJson()).toList(),
    'identifiers': identifiers,
    'languages': languages,
    'authors': authors.map((v) => v.toJson()).toList(),
    'contributors': contributors.map((v) => v.toJson()).toList(),
    'publishers': publishers.map((v) => v.toJson()).toList(),
    'subjects': subjects.map((v) => v.toJson()).toList(),
    if (description != null) 'description': description,
    if (rights != null) 'rights': rights,
    if (published != null) 'published': published!.toIso8601String(),
    if (modified != null) 'modified': modified!.toIso8601String(),
    if (duration != null) 'duration': duration!.inMicroseconds / 1000000,
    if (numberOfPages != null) 'numberOfPages': numberOfPages,
    'readingProgression': readingProgression,
    'layout': layout,
    if (orientation != null) 'orientation': orientation,
    if (spread != null) 'spread': spread,
    if (cover != null) 'cover': cover!.toJson(),
    'accessibility': accessibility,
    'belongsTo': belongsTo.map((v) => v.toJson()).toList(),
    'prefixes': prefixes,
    'properties': properties,
    'raw': raw.map((v) => v.toJson()).toList(),
  };
}
