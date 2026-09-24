import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../archive/archive.dart';
import '../archive/zip_archive.dart';
import '../asset/asset.dart';
import '../cfi/epub_cfi.dart';
import '../error/publication_exception.dart';
import '../fetcher/archive_fetcher.dart';
import '../fetcher/fetcher.dart';
import '../resource/resource.dart';
import '../util/publication_uri.dart';
import '../publication/model.dart';
import '../publication/publication.dart';

part 'package_reader.dart';
part 'package_manifest.dart';
part 'package_links.dart';
part 'metadata_reader.dart';
part 'metadata_support.dart';
part 'navigation.dart';
part 'encryption.dart';
part 'xml_support.dart';
part 'uri_support.dart';

/// Bounds XML and navigation processing for untrusted EPUB input.
final class EpubParserOptions {
  /// Creates EPUB parser limits and configuration.
  const EpubParserOptions({
    this.archiveLimits = const ArchiveLimits(),
    this.maxXmlBytes = 8 * 1024 * 1024,
    this.maxXmlElements = 100000,
    this.maxXmlDepth = 128,
    this.maxNavigationItems = 10000,
    this.maxNavigationDepth = 64,
  });

  /// ZIP processing limits.
  final ArchiveLimits archiveLimits;

  /// Maximum bytes in container, OPF, encryption, NCX, or nav XML.
  final int maxXmlBytes;

  /// Maximum elements parsed from one XML document.
  final int maxXmlElements;

  /// Maximum XML element nesting depth.
  final int maxXmlDepth;

  /// Maximum navigation links across one navigation document.
  final int maxNavigationItems;

  /// Maximum navigation hierarchy nesting depth.
  final int maxNavigationDepth;
}

/// A diagnostic for a recoverable EPUB interoperability issue.
final class EpubWarning {
  /// Creates an EPUB warning.
  const EpubWarning(this.code, this.message, {this.path});

  /// Stable warning identifier.
  final String code;

  /// Human-readable explanation.
  final String message;

  /// Related archive path, if known.
  final String? path;
}

/// A package-document spine entry, including non-linear items.
final class EpubSpineItem {
  const EpubSpineItem._(this.link, this.linear, this.cfiPath, this.idref);

  /// The content link, equal to its entry in the reading order or resources.
  final Link link;

  /// Whether the item belongs to the linear reading order.
  final bool linear;

  /// The EPUB CFI package path to this item's `itemref`, such as
  /// `/6/4[chap01ref]`.
  ///
  /// Step indices count every child element of the package and spine
  /// elements. The itemref `id`, when declared, is the step's ID assertion.
  final CfiPath cfiPath;

  /// The manifest item identifier referenced by the `itemref`.
  final String idref;
}

/// A parsed EPUB publication with lazy access to its contained resources.
final class EpubPublication implements Publication {
  EpubPublication._(
    this.metadata,
    this.links,
    this.readingOrder,
    this.resources,
    this.tableOfContents,
    this.landmarks,
    this.pageList,
    this.otherCollections,
    this.spine,
    this.warnings,
    this.encryption,
    this._fetcher,
    this._linksByHref,
    this._missing,
  );

  /// Opens and normalizes an EPUB 2 or EPUB 3 package from [asset].
  static Future<EpubPublication> open(
    Asset asset, {
    EpubParserOptions options = const EpubParserOptions(),
  }) async {
    if (options.maxXmlBytes <= 0 ||
        options.maxXmlElements <= 0 ||
        options.maxXmlDepth <= 0 ||
        options.maxNavigationItems <= 0 ||
        options.maxNavigationDepth <= 0) {
      throw const EpubException('EPUB parser limits must be positive.');
    }
    final archive = await ZipArchive.open(asset, limits: options.archiveLimits);
    final baseFetcher = ArchiveFetcher(archive);
    try {
      final parser = _EpubParser(baseFetcher, archive, options);
      return await parser.parse();
    } on Object {
      await baseFetcher.close();
      rethrow;
    }
  }

  /// Normalized publication metadata.
  @override
  final Metadata metadata;

  /// Publication-level links, including `self` and package links.
  @override
  final List<Link> links;

  /// Spine items in reading order. Non-linear items remain resources only.
  @override
  final List<Link> readingOrder;

  /// Manifest resources not in the linear reading order.
  @override
  final List<Link> resources;

  /// Table of contents entries.
  @override
  final List<Link> tableOfContents;

  /// Landmark navigation entries.
  @override
  final List<Link> landmarks;

  /// Page-list navigation entries.
  @override
  final List<Link> pageList;

  /// EPUB collection resources whose role is not a standard normalized list.
  @override
  final List<PublicationCollection> otherCollections;

  /// Spine entries in package order, including non-linear items.
  ///
  /// This preserves the document positions that EPUB CFI package paths refer
  /// to; [readingOrder] and [resources] remain the normalized lists.
  final List<EpubSpineItem> spine;

  /// Recoverable problems discovered while parsing.
  final List<EpubWarning> warnings;

  /// Encryption algorithm URIs by encoded publication-relative resource URI.
  ///
  /// Known font obfuscation is decoded by [resource]; other algorithms fail on
  /// read. This map preserves declarations for inspection without exposing XML.
  final Map<String, String> encryption;

  final Fetcher _fetcher;
  final Map<String, Link> _linksByHref;
  final Set<String> _missing;

  /// Returns [link] or the first resource of its manifest fallback chain that
  /// is present in the container and satisfies [accept]; null when none does.
  ///
  /// EPUB Reading Systems 3.3 requires fallbacks for foreign resources a
  /// reading system does not support; resources absent from the container are
  /// skipped the same way. [accept] receives manifest links, which carry the
  /// media type even when [link] is a navigation link. Remote resources are
  /// never accepted.
  Link? fallbackFor(Link link, bool Function(Link candidate) accept) {
    final seen = <String>{};
    Link? current = link;
    while (current != null) {
      final href = current.href.split(RegExp('[?#]')).first;
      if (!seen.add(href)) return null;
      final manifest = _linksByHref[href];
      if (!_missing.contains(href) &&
          !Uri.parse(href).hasScheme &&
          accept(manifest ?? current)) {
        return identical(current, link) ? link : manifest ?? current;
      }
      final next = (manifest ?? current).properties['fallback'];
      current = next == null ? null : _linksByHref[next];
    }
    return null;
  }

  /// Returns a lazy resource proxy for [link].
  @override
  Resource resource(Link link) => _PublicationResource(
    _fetcher,
    Uri.parse(link.href),
    link.type ?? _linksByHref[link.href.split(RegExp('[?#]')).first]?.type,
  );

  /// Looks up a manifest resource by its encoded publication-relative URI.
  @override
  Resource? get(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null) return null;
    final key = uri
        .replace(query: '', fragment: '')
        .toString()
        .split(RegExp('[?#]'))
        .first;
    final link = _linksByHref[href] ?? _linksByHref[key];
    return link == null ? null : resource(link);
  }

  /// Releases the archive and invalidates all lazy resource reads.
  @override
  Future<void> close() => _fetcher.close();
}

final class _EpubParser {
  _EpubParser(this.fetcher, this.archive, this.options);
  final ArchiveFetcher fetcher;
  final Archive archive;
  final EpubParserOptions options;
  final List<EpubWarning> warnings = [];

  Future<EpubPublication> parse() async {
    final mime = await _text('mimetype');
    if (mime != 'application/epub+zip') {
      throw const EpubException(
        'The EPUB mimetype entry is missing or invalid.',
        path: 'mimetype',
      );
    }
    final container = await _xml('META-INF/container.xml');
    if (!_matches(container.rootElement, 'container', _containerNs)) {
      throw const EpubException('Container root is not an OCF container.');
    }
    final roots = container.rootElement.childElements.firstWhereOrNull(
      (element) => _matches(element, 'rootfiles', _containerNs),
    );
    final rootfiles =
        roots?.childElements.where(
          (element) => _matches(element, 'rootfile', _containerNs),
        ) ??
        const <XmlElement>[];
    String? opfPath;
    for (final rootfile in rootfiles) {
      if (_attribute(rootfile, 'media-type') == 'application/oebps-package+xml') {
        final value = _attribute(rootfile, 'full-path');
        if (value != null) {
          opfPath = normalizeArchivePath(value);
          break;
        }
      }
    }
    if (opfPath == null) {
      throw const EpubException('No EPUB package rootfile was found.');
    }
    final opf = await _xml(opfPath);
    if (!_matches(opf.rootElement, 'package', _opfNs)) {
      throw EpubException('Package root is not an OPF package.', path: opfPath);
    }
    final package = await _PackageReader(opf, opfPath, this).read();
    final protected = await _encryption(opfPath, package.uniqueIdentifier);
    final securedFetcher = protected.isEmpty
        ? fetcher
        : _EncryptionFetcher(fetcher, protected);
    final allLinks = <Link>[...package.links];
    final byHref = {for (final link in allLinks) link.href: link};
    final missing = <String>{
      for (final link in allLinks)
        if (!Uri.parse(link.href).hasScheme &&
            archive.entry(resolvePublicationPath(Uri.parse(link.href))) == null)
          link.href,
    };
    return EpubPublication._(
      package.metadata,
      List.unmodifiable([
        Link(
          href: _uri(opfPath),
          type: 'application/oebps-package+xml',
          rels: const {'self'},
        ),
        ...package.publicationLinks,
      ]),
      List.unmodifiable(package.readingOrder),
      List.unmodifiable(package.resources),
      List.unmodifiable(package.toc),
      List.unmodifiable(package.landmarks),
      List.unmodifiable(package.pageList),
      List.unmodifiable(package.collections),
      List.unmodifiable(package.spine),
      List.unmodifiable(warnings),
      Map.unmodifiable({
        for (final entry in protected.entries) _uri(entry.key): entry.value.algorithm,
      }),
      securedFetcher,
      UnmodifiableMapView(byHref),
      Set.unmodifiable(missing),
    );
  }

  Future<String> _text(String path) async {
    final entry = archive.entry(path);
    if (entry == null || entry.isDirectory) {
      throw EpubException('Required EPUB document is missing.', path: path);
    }
    if (entry.size > options.maxXmlBytes) {
      throw EpubLimitException('XML document exceeds size limit.', path: path);
    }
    final bytes = await archive.read(path);
    if (bytes.length > options.maxXmlBytes) {
      throw EpubLimitException('XML document exceeds size limit.', path: path);
    }
    return _decodeXml(bytes, path);
  }

  Future<XmlDocument> _xml(String path) async =>
      _boundedXml(await _text(path), path, options);

  Future<Map<String, _FontEncryption>> _encryption(
    String opfPath,
    String? identifier,
  ) async {
    if (archive.entry('META-INF/encryption.xml') == null) return const {};
    final xml = await _xml('META-INF/encryption.xml');
    final result = <String, _FontEncryption>{};
    if (!_matches(xml.rootElement, 'encryption', _containerNs)) {
      throw const EpubSecurityException('Encryption metadata has an invalid root.');
    }
    for (final encrypted in xml.rootElement.childElements.where(
      (e) => _matches(e, 'EncryptedData', _encNs),
    )) {
      final method = encrypted.childElements.firstWhereOrNull(
        (e) => _matches(e, 'EncryptionMethod', _encNs),
      );
      final cipher = encrypted.childElements.firstWhereOrNull(
        (e) => _matches(e, 'CipherData', _encNs),
      );
      final reference = cipher?.childElements.firstWhereOrNull(
        (e) => _matches(e, 'CipherReference', _encNs),
      );
      final algorithm = method?.getAttribute('Algorithm');
      final uri = reference?.getAttribute('URI');
      if (algorithm == null || algorithm.isEmpty || uri == null || uri.isEmpty) {
        throw const EpubSecurityException('Encryption declaration is incomplete.');
      }
      final path = _resolveRoot(uri);
      if (result.containsKey(path)) {
        throw EpubSecurityException('Duplicate encryption declaration.', path: path);
      }
      final kind = switch (algorithm) {
        'http://www.idpf.org/2008/embedding' => _EncryptionKind.idpf,
        'http://ns.adobe.com/pdf/enc#RC' => _EncryptionKind.adobe,
        _ => _EncryptionKind.unsupported,
      };
      result[path] = _FontEncryption(kind, identifier, algorithm);
    }
    return result;
  }
}
