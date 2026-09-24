import 'dart:typed_data';

import '../archive/archive.dart';
import '../error/publication_exception.dart';
import '../resource/resource.dart';
import '../util/publication_uri.dart';
import 'fetcher.dart';

/// A [Fetcher] over the files held by an [Archive].
final class ArchiveFetcher implements Fetcher {
  /// Creates a fetcher for [archive].
  ArchiveFetcher(this.archive);

  /// The backing archive owned by this fetcher.
  final Archive archive;
  bool _closed = false;

  @override
  Future<Resource?> get(Uri href) async {
    _ensureOpen();
    final entry = archive.entry(resolvePublicationPath(href));
    return entry == null || entry.isDirectory
        ? null
        : _ArchiveResource(archive, href, entry);
  }

  @override
  Future<Resource> open(Uri href) async {
    final resource = await get(href);
    if (resource == null) {
      throw ResourceException('Resource was not found.', path: href.toString());
    }
    return resource;
  }

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      await archive.close();
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const ResourceException('Fetcher is closed.');
    }
  }
}

final class _ArchiveResource implements Resource {
  const _ArchiveResource(this._archive, this.href, this._entry);

  final Archive _archive;
  final ArchiveEntry _entry;

  @override
  final Uri href;

  @override
  String? get mediaType => _mediaTypeForPath(_entry.path);

  @override
  Future<int?> get length async => _entry.size;

  @override
  Future<Uint8List> read({int? start, int? end}) =>
      _archive.read(_entry.path, start: start, end: end);
}

String? _mediaTypeForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot <= path.lastIndexOf('/')) return null;
  return switch (path.substring(dot + 1).toLowerCase()) {
    'css' => 'text/css',
    'gif' => 'image/gif',
    'htm' || 'html' => 'text/html',
    'jpeg' || 'jpg' => 'image/jpeg',
    'ncx' => 'application/x-dtbncx+xml',
    'opf' => 'application/oebps-package+xml',
    'png' => 'image/png',
    'svg' => 'image/svg+xml',
    'xhtml' => 'application/xhtml+xml',
    'xml' => 'application/xml',
    _ => null,
  };
}
