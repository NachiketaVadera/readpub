part of 'epub_publication.dart';

final class _MetadataReader {
  _MetadataReader(this.element, this.package, this.parser, this.path)
    : prefixes = _prefixes(package) {
    records = _metadataRecords(element, prefixes);
    for (final record in records) {
      final refines = record.refines;
      if (refines != null && refines.startsWith('#')) {
        refinements.putIfAbsent(refines.substring(1), () => []).add(record);
      }
    }
  }
  final XmlElement element;
  final XmlElement package;
  final _EpubParser parser;
  final String path;
  final Map<String, String> prefixes;
  List<MetadataRecord> records = [];
  final Map<String, List<MetadataRecord>> refinements = {};

  List<String> refined(String? id, String property) => id == null
      ? const []
      : [
          for (final record in refinements[id] ?? const <MetadataRecord>[])
            if (record.namespace == _opfNs &&
                record.property == _expandProperty(property, prefixes))
              record.value,
        ];
  String? refinement(String? id, String property) => refined(id, property).firstOrNull;
  List<XmlElement> dc(String name) =>
      element.childElements.where((e) => _matches(e, name, _dcNs)).toList();
  String? value(String name) =>
      dc(name).map((e) => _clean(e.innerText)).where((s) => s.isNotEmpty).firstOrNull;

  String? property(String name) => records
      .where(
        (record) =>
            record.namespace == _opfNs &&
            record.refines == null &&
            record.property == _expandProperty(name, prefixes),
      )
      .map((record) => record.value)
      .firstOrNull;

  String? legacy(String name) => records
      .where(
        (record) =>
            record.namespace == _opfNs &&
            record.name.split(':').last == 'meta' &&
            record.attributes['name'] == name,
      )
      .map((record) => record.value)
      .firstOrNull;

  String? get uniqueIdentifier {
    final id = package.getAttribute('unique-identifier');
    return dc('identifier')
        .where((e) => e.getAttribute('id') == id && id != null)
        .map((e) => e.innerText)
        .firstOrNull;
  }

  Contributor contributor(XmlElement node, String defaultRole) {
    final id = node.getAttribute('id');
    final roles = refined(
      id,
      'role',
    ).map((role) => role.contains('/') ? role.split('/').last : role).toSet();
    if (roles.isEmpty) {
      roles.add(node.getAttribute('role', namespaceUri: _opfNs) ?? defaultRole);
    }
    return Contributor(
      name: _clean(node.innerText),
      roles: roles,
      fileAs:
          refinement(id, 'file-as') ??
          node.getAttribute('file-as', namespaceUri: _opfNs),
      identifier: refinement(id, 'identifier'),
      language: _language(node),
      direction: _direction(node),
    );
  }

  Metadata build({required String readingProgression, Link? cover}) {
    final titleElements = dc('title');
    final titleIndices = {
      for (final (index, element) in titleElements.indexed) element: index,
    };
    final ordered = [...titleElements]
      ..sort((a, b) {
        final left =
            int.tryParse(refinement(a.getAttribute('id'), 'display-seq') ?? '') ??
            2147483647;
        final right =
            int.tryParse(refinement(b.getAttribute('id'), 'display-seq') ?? '') ??
            2147483647;
        return left == right
            ? (titleIndices[a] ?? 0).compareTo(titleIndices[b] ?? 0)
            : left.compareTo(right);
      });
    final main =
        ordered
            .where((e) => refinement(e.getAttribute('id'), 'title-type') == 'main')
            .firstOrNull ??
        ordered
            .where((e) => refinement(e.getAttribute('id'), 'title-type') != 'subtitle')
            .firstOrNull ??
        ordered.firstOrNull;
    final subtitle = ordered
        .where((e) => refinement(e.getAttribute('id'), 'title-type') == 'subtitle')
        .firstOrNull;
    final authors = <Contributor>[];
    final contributors = <Contributor>[];
    for (final node in [...dc('creator'), ...dc('contributor')]) {
      final item = contributor(node, _matches(node, 'creator', _dcNs) ? 'aut' : 'ctb');
      if (item.name.isNotEmpty) {
        (item.roles.contains('aut') ? authors : contributors).add(item);
      }
    }
    final properties = <String, String>{};
    final accessibility = <String, List<String>>{};
    for (final record in records.where(
      (r) => r.namespace == _opfNs && r.refines == null,
    )) {
      final prop = record.property;
      if (prop == null) continue;
      final name = _canonicalProperty(prop);
      properties.putIfAbsent(name, () => record.value);
      if (name.startsWith('schema:access') || name.startsWith('schema:certified')) {
        accessibility.putIfAbsent(name.substring(7), () => []).add(record.value);
      }
    }
    final publishedElement =
        dc('date')
            .where(
              (e) => e.getAttribute('event', namespaceUri: _opfNs) == 'publication',
            )
            .firstOrNull ??
        dc('date').firstOrNull;
    final publishedSource = publishedElement == null
        ? null
        : _clean(publishedElement.innerText);
    final modifiedSource = property('dcterms:modified');
    final durationSource = property('media:duration');
    final published = _date(publishedSource);
    final modified = _date(modifiedSource);
    final duration = _clock(durationSource);
    for (final invalid in <(String, String?, Object?)>[
      ('published', publishedSource, published),
      ('modified', modifiedSource, modified),
      ('duration', durationSource, duration),
    ]) {
      if (invalid.$2 != null && invalid.$3 == null) {
        parser.warnings.add(
          EpubWarning(
            'metadata-invalid-${invalid.$1}',
            'Ignoring invalid ${invalid.$1} value.',
            path: path,
          ),
        );
      }
    }
    final pages = int.tryParse(
      property('schema:numberOfPages') ?? property('number-of-pages') ?? '',
    );
    final belongsTo = <CollectionMembership>[];
    for (final record in records.where(
      (r) =>
          r.namespace == _opfNs &&
          r.refines == null &&
          r.property == '$_metaVocab${'belongs-to-collection'}',
    )) {
      final position = double.tryParse(refinement(record.id, 'group-position') ?? '');
      belongsTo.add(
        CollectionMembership(
          record.value,
          type: refinement(record.id, 'collection-type'),
          position: position != null && position.isFinite ? position : null,
        ),
      );
    }
    final calibreSeries = legacy('calibre:series');
    if (calibreSeries != null && belongsTo.isEmpty) {
      final position = double.tryParse(legacy('calibre:series_index') ?? '');
      belongsTo.add(
        CollectionMembership(
          calibreSeries,
          type: 'series',
          position: position != null && position.isFinite ? position : null,
        ),
      );
    }
    final title = main == null ? '' : _clean(main.innerText);
    for (final missing in <String, bool>{
      'title': title.isEmpty,
      'identifier': uniqueIdentifier == null,
      'language': dc('language').isEmpty,
    }.entries) {
      if (missing.value) {
        parser.warnings.add(
          EpubWarning(
            'metadata-missing-${missing.key}',
            'Package has no usable ${missing.key}.',
            path: path,
          ),
        );
      }
    }
    return Metadata(
      title: title,
      subtitle: subtitle == null ? null : _clean(subtitle.innerText),
      titles: ordered.map(
        (e) => LocalizedString(
          _clean(e.innerText),
          language: _language(e),
          direction: _direction(e),
          id: e.getAttribute('id'),
        ),
      ),
      identifier: uniqueIdentifier?.trim() ?? value('identifier'),
      identifiers: dc('identifier').map((e) => _clean(e.innerText)),
      languages: dc('language')
          .map((e) => _clean(e.innerText))
          .where((v) => v.isNotEmpty),
      authors: authors,
      contributors: contributors,
      publishers: dc('publisher').map((e) => contributor(e, 'pbl')),
      subjects: dc('subject').map(
        (e) => Subject(
          _clean(e.innerText),
          scheme: refinement(e.getAttribute('id'), 'authority'),
          code: refinement(e.getAttribute('id'), 'term'),
        ),
      ),
      description: value('description'),
      rights: value('rights'),
      published: published,
      modified: modified,
      duration: duration,
      numberOfPages: pages != null && pages > 0 ? pages : null,
      readingProgression: readingProgression,
      layout: property('rendition:layout') == 'pre-paginated' ? 'fixed' : 'reflowable',
      orientation: property('rendition:orientation'),
      spread: property('rendition:spread'),
      cover: cover,
      accessibility: accessibility,
      belongsTo: belongsTo,
      raw: records,
      properties: properties,
      prefixes: prefixes,
    );
  }
}
