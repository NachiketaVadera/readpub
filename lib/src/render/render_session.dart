import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../content/content_source.dart';
import '../epub/epub_publication.dart';
import '../error/publication_exception.dart';
import '../publication/model.dart';
import '../publication/publication.dart';
import '../util/publication_uri.dart';
import 'render_settings.dart';

part 'document_preparer.dart';

/// A prepared chapter and the loopback URL from which it is served.
final class RenderedChapter {
  /// Creates a prepared chapter.
  const RenderedChapter({
    required this.url,
    required this.html,
    required this.mediaType,
  });

  /// The URL to load in a browser or WebView.
  final Uri url;

  /// The prepared XHTML or HTML source.
  final String html;

  /// The response media type.
  final String mediaType;
}

/// Serves publication content to a browser or WebView over loopback HTTP.
///
/// The caller owns [publication] and closes it separately after [close].
/// Script execution is blocked by the response policy. A host WebView should
/// also disable JavaScript and decide how outbound navigation is handled.
final class EpubRenderSession {
  EpubRenderSession._(
    this.publication,
    this._server,
    this._token,
    this._linksByPath,
    this._spineByPath,
    this._settings,
    this.maxDocumentBytes,
    this.maxElements,
    this.maxDepth,
  );

  /// Starts a local rendering origin for [publication].
  ///
  /// Chapters are loaded only when requested by a browser. Non-document
  /// resources are served directly from the publication, preserving font
  /// deobfuscation and resource range reads.
  static Future<EpubRenderSession> start(
    Publication publication, {
    ReaderSettings? settings,
    int maxDocumentBytes = 8 * 1024 * 1024,
    int maxElements = 100000,
    int maxDepth = 128,
  }) async {
    checkContentLimits(maxDocumentBytes, maxElements, maxDepth);
    final links = <String, Link>{};
    for (final link in [...publication.readingOrder, ...publication.resources]) {
      if (link.href.isEmpty) continue;
      final uri = Uri.parse(link.href);
      if (uri.hasScheme || uri.hasAuthority) continue;
      final path = resolvePublicationPath(uri);
      links.putIfAbsent(path, () => link);
    }
    // Fallback documents displayed for reading-order items keep the spine
    // item's rendition properties.
    final spine = <String, Link>{};
    for (final link in publication.readingOrder) {
      final content = _fallback(publication, link, displayableContentTypes);
      if (!identical(content, link)) {
        spine.putIfAbsent(resolvePublicationPath(Uri.parse(content.href)), () => link);
      }
    }
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final token = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final session = EpubRenderSession._(
      publication,
      server,
      token,
      Map.unmodifiable(links),
      Map.unmodifiable(spine),
      settings ?? ReaderSettings(),
      maxDocumentBytes,
      maxElements,
      maxDepth,
    );
    server.listen((request) => unawaited(session._handle(request)));
    return session;
  }

  /// The publication supplying resource bytes.
  final Publication publication;

  /// The maximum chapter bytes materialized for preparation.
  final int maxDocumentBytes;

  /// The maximum XHTML elements or legacy HTML nodes.
  final int maxElements;

  /// The maximum XHTML or legacy HTML nesting depth.
  final int maxDepth;

  final HttpServer _server;
  final String _token;
  final Map<String, Link> _linksByPath;
  final Map<String, Link> _spineByPath;
  ReaderSettings _settings;
  bool _closed = false;

  /// The current display preferences.
  ReaderSettings get settings => _settings;

  /// Whether the loopback origin has been closed.
  bool get isClosed => _closed;

  /// Changes preferences for subsequent chapter loads.
  ///
  /// Reload the current browser page after calling this method.
  void updateSettings(ReaderSettings settings) {
    if (_closed) throw StateError('Rendering session is closed.');
    _settings = settings;
  }

  /// Returns a browser URL for a local publication [link].
  ///
  /// A navigation link may contain a query and fragment. The archive lookup
  /// ignores them while the browser keeps them for navigation. When the linked
  /// resource cannot be displayed by a browser, or is missing, the URL of the
  /// first displayable resource in its manifest fallback chain is returned.
  Uri urlFor(Link link) {
    if (_closed) throw StateError('Rendering session is closed.');
    final uri = Uri.parse(link.href);
    if (uri.hasScheme || uri.hasAuthority || link.href.isEmpty) {
      throw ResourceException(
        'Rendering requires a local manifest link.',
        path: link.href,
      );
    }
    final path = resolvePublicationPath(uri);
    final item = _linksByPath[path];
    if (item == null) {
      throw ResourceException('Resource is absent from the manifest.', path: link.href);
    }
    final content = _fallback(publication, item, displayableContentTypes);
    if (!identical(content, item)) return baseUrl.resolve(content.href);
    return baseUrl.resolveUri(uri);
  }

  /// The private loopback base URL for this publication.
  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}/$_token/');

  /// The contents page listing the publication's reading order and TOC.
  Uri get indexUrl => baseUrl;

  /// Prepares an XHTML or HTML chapter for display.
  Future<RenderedChapter> prepare(Link link) async {
    final url = urlFor(link);
    final path = resolvePublicationReference(url.path.substring(baseUrl.path.length));
    final item = _linksByPath[path]!;
    final spine = _spineByPath[path] ?? item;
    final type = item.type;
    if (type != 'application/xhtml+xml' && type != 'text/html') {
      throw ResourceException('Resource is not an HTML content document.', path: path);
    }
    final resource = publication.resource(item);
    final declaredSize = await resource.length;
    if (declaredSize != null && declaredSize > maxDocumentBytes) {
      throw ContentException('Content document exceeds byte limit.', path: path);
    }
    final bytes = await resource.read();
    if (bytes.length > maxDocumentBytes) {
      throw ContentException('Content document exceeds byte limit.', path: path);
    }
    final fixed = switch (spine.properties['layout'] ?? item.properties['layout']) {
      'fixed' => true,
      'reflowable' => false,
      _ => publication.metadata.layout == 'fixed',
    };
    final html = type == 'application/xhtml+xml'
        ? _prepareXhtml(
            bytes,
            path,
            _settings,
            documentHref: item.href,
            fixedLayout: fixed,
            maxElements: maxElements,
            maxDepth: maxDepth,
          )
        : _prepareHtml(
            bytes,
            path,
            _settings,
            documentHref: item.href,
            fixedLayout: fixed,
            maxElements: maxElements,
            maxDepth: maxDepth,
          );
    return RenderedChapter(url: url, html: html, mediaType: type!);
  }

  /// Stops serving resources without closing [publication].
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'private, no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
    response.headers.set('X-Frame-Options', 'DENY');
    response.headers.set('Content-Security-Policy', _contentPolicy);
    try {
      if (_closed ||
          request.headers.host != '127.0.0.1' ||
          request.headers.port != _server.port ||
          (request.method != 'GET' && request.method != 'HEAD')) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      final target = request.uri.toString().split('?').first;
      final prefix = '/$_token/';
      if (!target.startsWith(prefix)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (target == prefix) {
        final bytes = utf8.encode(_indexHtml());
        response.headers.contentType = ContentType.parse('text/html; charset=utf-8');
        response.contentLength = bytes.length;
        if (request.method == 'GET') {
          response.add(bytes);
        }
        return;
      }
      final encodedPath = target.substring(prefix.length);
      final path = resolvePublicationReference(encodedPath);
      final requested = _linksByPath[path];
      if (requested == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      // Foreign resources are replaced by the first supported resource in
      // their manifest fallback chain.
      final link = _fallback(publication, requested, _servedTypes);
      final document = link.type == 'application/xhtml+xml' || link.type == 'text/html';
      if (document) {
        final prepared = await prepare(link);
        final bytes = utf8.encode(prepared.html);
        response.headers.contentType = ContentType.parse(
          '${prepared.mediaType}; charset=utf-8',
        );
        response.contentLength = bytes.length;
        if (request.method == 'GET') {
          response.add(bytes);
        }
        return;
      }
      final resource = publication.resource(link);
      final length = await resource.length;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final bounds = range == null || length == null
          ? null
          : _parseRange(range, length);
      if (range != null && bounds == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        if (length != null) {
          response.headers.set('Content-Range', 'bytes */$length');
        }
        return;
      }
      response.headers.contentType = ContentType.parse(
        link.type ?? 'application/octet-stream',
      );
      response.headers.set('Accept-Ranges', 'bytes');
      if (bounds case (final start, final end)) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set('Content-Range', 'bytes $start-${end - 1}/$length');
        response.contentLength = end - start;
        if (request.method == 'GET') {
          response.add(await resource.read(start: start, end: end));
        }
      } else {
        if (length != null) {
          response.contentLength = length;
        }
        if (request.method == 'GET') {
          response.add(await resource.read());
        }
      }
    } on PublicationException {
      response.statusCode = HttpStatus.forbidden;
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
    } on Object {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  String _indexHtml() {
    final title = _escapeHtml(publication.metadata.title);
    final output = StringBuffer('''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title</title><style>
:root{font:18px/1.5 system-ui,sans-serif;color:#222;background:#faf8f3}
body{max-width:48rem;margin:2rem auto;padding:0 1rem}
a{color:#215989}li{margin:.45rem 0}ol{padding-inline-start:1.6rem}
</style></head><body><main><h1>$title</h1><h2>Reading order</h2><ol>''');
    for (final link in publication.readingOrder) {
      final label = _escapeHtml(link.title ?? Uri.parse(link.href).pathSegments.last);
      final url = _escapeHtml(urlFor(link).toString());
      output.write('<li><a href="$url">$label</a></li>');
    }
    output.write('</ol>');
    if (publication.tableOfContents.isNotEmpty) {
      output.write('<h2>Contents</h2>');
      void writeLinks(List<Link> links) {
        output.write('<ol>');
        for (final link in links) {
          output.write('<li>');
          final label = _escapeHtml(link.title ?? link.href);
          try {
            final url = _escapeHtml(urlFor(link).toString());
            output.write('<a href="$url">$label</a>');
          } on PublicationException {
            output.write(label);
          }
          if (link.children.isNotEmpty) writeLinks(link.children);
          output.write('</li>');
        }
        output.write('</ol>');
      }

      writeLinks(publication.tableOfContents);
    }
    output.write('</main></body></html>');
    return output.toString();
  }
}

/// Resource types served without following manifest fallbacks.
const _servedTypes = {...coreMediaTypes, 'text/html', 'image/avif'};

/// Returns [link], or its first fallback whose media type is in [types].
Link _fallback(Publication publication, Link link, Set<String> types) =>
    publication is EpubPublication
    ? publication.fallbackFor(link, (item) => types.contains(item.type)) ?? link
    : link;

String _escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

(int, int)? _parseRange(String header, int length) {
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
  if (match == null || length == 0) return null;
  final first = match.group(1)!;
  final last = match.group(2)!;
  if (first.isEmpty && last.isEmpty) return null;
  if (first.isEmpty) {
    final suffix = int.tryParse(last);
    if (suffix == null || suffix <= 0) return null;
    return (max(0, length - suffix), length);
  }
  final start = int.tryParse(first);
  final inclusiveEnd = last.isEmpty ? length - 1 : int.tryParse(last);
  if (start == null ||
      inclusiveEnd == null ||
      start >= length ||
      start > inclusiveEnd) {
    return null;
  }
  return (start, min(length, inclusiveEnd + 1));
}

const _contentPolicy =
    "default-src 'none'; img-src 'self' data:; "
    "font-src 'self' data:; style-src 'self' 'unsafe-inline'; "
    "media-src 'self' data:; script-src 'none'; connect-src 'none'; "
    "frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
