import 'package:collection/collection.dart';

part 'metadata.dart';
part 'link.dart';

const _equality = DeepCollectionEquality();

abstract class _ValueModel {
  const _ValueModel();

  /// Serializes the normalized value to JSON-compatible data.
  Map<String, Object?> toJson();
  @override
  bool operator ==(Object other) =>
      other is _ValueModel &&
      runtimeType == other.runtimeType &&
      _equality.equals(toJson(), other.toJson());
  @override
  int get hashCode => _equality.hash(toJson());
  @override
  String toString() => '$runtimeType(${toJson()})';
}

/// A string with an optional language and source identifier.
final class LocalizedString extends _ValueModel {
  /// Creates a localized string.
  const LocalizedString(this.value, {this.language, this.direction, this.id});

  /// The textual value.
  final String value;

  /// The BCP 47 language tag, if supplied.
  final String? language;

  /// The base direction, `ltr`, `rtl` or `auto`, declared on the element or
  /// inherited from the package; null when undeclared.
  final String? direction;

  /// The source identifier, if supplied.
  final String? id;
  @override
  Map<String, Object?> toJson() => {
    'value': value,
    if (language != null) 'language': language,
    if (direction != null) 'direction': direction,
    if (id != null) 'id': id,
  };
}

/// A source metadata record retained alongside normalized metadata.
final class MetadataRecord extends _ValueModel {
  /// Creates a metadata record with a defensive copy of its attributes.
  MetadataRecord({
    required this.name,
    required this.value,
    this.namespace,
    this.id,
    this.refines,
    this.scheme,
    this.language,
    this.property,
    Map<String, String> attributes = const {},
  }) : attributes = Map.unmodifiable(attributes);

  /// The source element's qualified name.
  final String name;

  /// The namespace URI of the source element.
  final String? namespace;

  /// The normalized textual value, or legacy metadata content attribute.
  final String value;

  /// The element identifier.
  final String? id;

  /// The resource or metadata fragment refined by this record.
  final String? refines;

  /// The declared scheme.
  final String? scheme;

  /// The inherited language.
  final String? language;

  /// The expanded vocabulary URI for a property, when present.
  final String? property;

  /// The original attributes, retaining their source prefixes.
  final Map<String, String> attributes;
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'value': value,
    if (namespace != null) 'namespace': namespace,
    if (id != null) 'id': id,
    if (refines != null) 'refines': refines,
    if (scheme != null) 'scheme': scheme,
    if (language != null) 'language': language,
    if (property != null) 'property': property,
    'attributes': attributes,
  };
}

/// A named person or organization associated with a publication.
final class Contributor extends _ValueModel {
  /// Creates an immutable contributor.
  Contributor({
    required this.name,
    Iterable<String> roles = const {},
    this.fileAs,
    this.identifier,
    this.language,
    this.direction,
  }) : roles = Set.unmodifiable(roles);

  /// The display name.
  final String name;

  /// The MARC relator codes or declared roles.
  final Set<String> roles;

  /// The sort name.
  final String? fileAs;

  /// The contributor identifier, if supplied.
  final String? identifier;

  /// The language of the name.
  final String? language;

  /// The base direction of the name, `ltr`, `rtl` or `auto`, declared on the
  /// element or inherited from the package; null when undeclared.
  final String? direction;
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'roles': roles.toList()..sort(),
    if (fileAs != null) 'fileAs': fileAs,
    if (identifier != null) 'identifier': identifier,
    if (language != null) 'language': language,
    if (direction != null) 'direction': direction,
  };
}

/// A publication subject with optional controlled-vocabulary information.
final class Subject extends _ValueModel {
  /// Creates a subject.
  const Subject(this.name, {this.code, this.scheme});

  /// The human-readable subject.
  final String name;

  /// The vocabulary term or code.
  final String? code;

  /// The vocabulary authority or scheme.
  final String? scheme;
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    if (code != null) 'code': code,
    if (scheme != null) 'scheme': scheme,
  };
}

/// Membership in a series or another named collection.
final class CollectionMembership extends _ValueModel {
  /// Creates a collection membership.
  const CollectionMembership(this.name, {this.type, this.position});

  /// The collection title.
  final String name;

  /// The collection type, such as `series`.
  final String? type;

  /// The ordinal position, when supplied.
  final double? position;
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    if (type != null) 'type': type,
    if (position != null) 'position': position,
  };
}
