part of 'epub_publication.dart';

const _metaVocab = 'http://idpf.org/epub/vocab/package/meta/#';
const _reservedPrefixes = <String, String>{
  'dcterms': 'http://purl.org/dc/terms/',
  'rendition': 'http://www.idpf.org/vocab/rendition/#',
  'media': 'http://www.idpf.org/epub/vocab/overlays/#',
  'schema': 'http://schema.org/',
  'marc': 'http://id.loc.gov/vocabulary/relators/',
};

Map<String, String> _prefixes(XmlElement package) {
  final values = <String, String>{..._reservedPrefixes};
  final declaration = package.getAttribute('prefix') ?? '';
  for (final match in RegExp(r'([A-Za-z][\w.-]*):\s+(\S+)').allMatches(declaration)) {
    final name = match.group(1);
    final uri = match.group(2);
    if (name != null && uri != null && Uri.tryParse(uri)?.hasScheme == true) {
      values[name] = uri;
    }
  }
  return values;
}

String _expandProperty(String property, Map<String, String> prefixes) {
  final colon = property.indexOf(':');
  if (colon == -1) return '$_metaVocab$property';
  final prefix = prefixes[property.substring(0, colon)];
  return prefix == null ? property : '$prefix${property.substring(colon + 1)}';
}

String _canonicalProperty(String expanded) {
  if (expanded.startsWith(_metaVocab)) return expanded.substring(_metaVocab.length);
  for (final entry in _reservedPrefixes.entries) {
    if (expanded.startsWith(entry.value)) {
      return '${entry.key}:${expanded.substring(entry.value.length)}';
    }
  }
  if (expanded.startsWith('https://schema.org/')) {
    return 'schema:${expanded.substring(19)}';
  }
  return expanded;
}

String? _language(XmlElement element) {
  for (XmlNode? node = element; node != null; node = node.parent) {
    if (node is XmlElement) {
      final value = node.getAttribute('lang', namespaceUri: _xmlNs);
      if (value != null) return value.isEmpty ? null : value;
    }
  }
  return null;
}

/// The inherited `dir` attribute: `ltr`, `rtl` or `auto`, else null.
String? _direction(XmlElement element) {
  for (XmlNode? node = element; node != null; node = node.parent) {
    if (node is XmlElement) {
      final value = node.getAttribute('dir')?.trim().toLowerCase();
      if (value != null) return {'ltr', 'rtl', 'auto'}.contains(value) ? value : null;
    }
  }
  return null;
}

List<MetadataRecord> _metadataRecords(
  XmlElement element,
  Map<String, String> prefixes,
) => [
  for (final child in element.childElements)
    MetadataRecord(
      name: child.name.qualified,
      namespace: child.name.namespaceUri,
      value: _matches(child, 'meta', _opfNs) && child.getAttribute('content') != null
          ? child.getAttribute('content') ?? ''
          : _clean(child.innerText),
      id: child.getAttribute('id'),
      refines: child.getAttribute('refines'),
      scheme: child.getAttribute('scheme'),
      language: _language(child),
      property:
          _matches(child, 'meta', _opfNs) && child.getAttribute('property') != null
          ? _expandProperty(child.getAttribute('property') ?? '', prefixes)
          : null,
      attributes: {
        for (final attr in child.attributes) attr.name.qualified: attr.value,
      },
    ),
];

Duration? _clock(String? source) {
  if (source == null) return null;
  final text = source.trim();
  double? seconds;
  if (text.contains(':')) {
    final parts = text.split(':');
    if (parts.length != 2 && parts.length != 3) return null;
    final values = parts.map(double.tryParse).toList();
    if (values.any((v) => v == null || !v.isFinite || v < 0)) return null;
    final last = values.last ?? 0;
    final minutes = values[values.length - 2] ?? 0;
    if (last >= 60 || minutes >= 60 || minutes != minutes.floorToDouble()) return null;
    final hours = values.length == 3 ? values.first ?? 0 : 0.0;
    if (hours != hours.floorToDouble()) return null;
    seconds = hours * 3600 + minutes * 60 + last;
  } else {
    final match = RegExp(r'^(\d+(?:\.\d+)?)(h|min|ms|s)?$').firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1) ?? '');
    if (value == null || !value.isFinite) return null;
    seconds =
        value *
        switch (match.group(2)) {
          'h' => 3600,
          'min' => 60,
          'ms' => 0.001,
          _ => 1,
        };
  }
  if (!seconds.isFinite || seconds > 9000000000) return null;
  return Duration(microseconds: (seconds * 1000000).round());
}

DateTime? _date(String? value) {
  if (value == null) return null;
  var normalized = value.trim();
  if (RegExp(r'^\d{4}$').hasMatch(normalized)) normalized += '-01-01';
  if (RegExp(r'^\d{4}-\d{2}$').hasMatch(normalized)) normalized += '-01';
  final result = DateTime.tryParse(normalized);
  final components = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(normalized);
  if (result == null || components == null) return null;
  // Validate calendar fields separately from timezone conversion.
  final year = int.parse(components.group(1) ?? '0');
  final month = int.parse(components.group(2) ?? '0');
  final day = int.parse(components.group(3) ?? '0');
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day ? result : null;
}
