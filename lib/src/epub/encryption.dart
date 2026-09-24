part of 'epub_publication.dart';

enum _EncryptionKind { idpf, adobe, unsupported }

final class _FontEncryption {
  const _FontEncryption(this.kind, this.identifier, this.algorithm);
  final _EncryptionKind kind;
  final String algorithm;
  final String? identifier;
}

final class _EncryptionFetcher implements Fetcher {
  _EncryptionFetcher(this._source, this._rules);
  final Fetcher _source;
  final Map<String, _FontEncryption> _rules;

  @override
  Future<Resource?> get(Uri href) async {
    final item = await _source.get(href);
    if (item == null) return null;
    final path = resolvePublicationPath(href);
    final rule = _rules[path];
    return rule == null ? item : _EncryptedResource(item, rule, path);
  }

  @override
  Future<Resource> open(Uri href) async =>
      (await get(href)) ??
      (throw ResourceException('Resource was not found.', path: href.toString()));

  @override
  Future<void> close() => _source.close();
}

final class _PublicationResource implements Resource {
  const _PublicationResource(this.fetcher, this.href, this.type);
  final Fetcher fetcher;
  @override
  final Uri href;
  final String? type;

  @override
  String? get mediaType => type;

  @override
  Future<int?> get length async => (await fetcher.open(href)).length;

  @override
  Future<Uint8List> read({int? start, int? end}) async =>
      (await fetcher.open(href)).read(start: start, end: end);
}

final class _EncryptedResource implements Resource {
  const _EncryptedResource(this._source, this._rule, this._path);
  final Resource _source;
  final _FontEncryption _rule;
  final String _path;

  @override
  Uri get href => _source.href;
  @override
  String? get mediaType => _source.mediaType;
  @override
  Future<int?> get length => _source.length;

  @override
  Future<Uint8List> read({int? start, int? end}) async {
    if (_rule.kind == _EncryptionKind.unsupported) {
      throw ResourceException(
        'EPUB resource uses unsupported encryption.',
        path: _path,
      );
    }
    final identifier = _rule.identifier;
    if (identifier == null || identifier.isEmpty) {
      throw ResourceException(
        'Font obfuscation has no package identifier.',
        path: _path,
      );
    }
    // Remove only XML whitespace, as required by the IDPF algorithm.
    final key = _rule.kind == _EncryptionKind.idpf
        ? sha1
              .convert(
                utf8.encode(identifier.replaceAll(RegExp(r'[\x20\x09\x0d\x0a]'), '')),
              )
              .bytes
        : _adobeKey(identifier);
    final offset = start ?? 0;
    final bytes = await _source.read(start: start, end: end);
    final prefixLength = _rule.kind == _EncryptionKind.idpf ? 1040 : 1024;
    for (var i = 0; i < bytes.length && offset + i < prefixLength; i++) {
      bytes[i] ^= key[(offset + i) % key.length];
    }
    return bytes;
  }
}

List<int> _adobeKey(String value) {
  var uuid = value.trim();
  if (uuid.toLowerCase().startsWith('urn:uuid:')) uuid = uuid.substring(9);
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(uuid)) {
    throw const ResourceException('Adobe font obfuscation requires a UUID identifier.');
  }
  final hex = uuid.replaceAll('-', '');
  return [
    for (var i = 0; i < 32; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
