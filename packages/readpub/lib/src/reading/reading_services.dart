import 'dart:collection';
import 'dart:math';

import '../cfi/epub_cfi.dart';
import '../content/content_source.dart';
import '../content/document_text.dart';
import '../epub/epub_publication.dart';
import '../error/publication_exception.dart';
import '../locator/locator.dart';
import '../publication/model.dart';
import '../publication/publication.dart';
import '../search/search.dart';
import '../util/publication_uri.dart';

part 'positions.dart';

/// The representation used to resolve a [Locator].
enum LocatorMatch {
  /// The content-document CFI, possibly corrected by its assertions.
  cfi,

  /// The surrounding or highlighted text.
  text,

  /// A fragment identifier.
  fragment,

  /// The progression within the resource.
  progression,

  /// The publication position.
  position,

  /// No usable location; the start of the resource.
  start,
}

/// A locator resolved against the current publication content.
final class LocatorResolution {
  const LocatorResolution._({
    required this.locator,
    required this.link,
    required this.readingOrderIndex,
    required this.start,
    required this.end,
    required this.contentCfi,
    required this.cfi,
    required this.match,
  });

  /// A refreshed locator whose CFI, progression, position and text describe
  /// the resolved location. Store it to replace a corrected locator.
  final Locator locator;

  /// The resource containing the location.
  final Link link;

  /// The reading-order index, or null for a resource outside it.
  final int? readingOrderIndex;

  /// The start offset in the resource's [DocumentText], or 0 without text.
  final int start;

  /// The end offset; greater than [start] when a highlight was resolved.
  final int end;

  /// The content-document CFI to navigate to, or null without text mapping.
  ///
  /// It is a range when a highlight was resolved.
  final EpubCfi? contentCfi;

  /// The publication CFI, when the publication is an EPUB.
  final EpubCfi? cfi;

  /// The representation that determined the location.
  final LocatorMatch match;
}

/// A resolved publication resource reference.
final class _Target {
  const _Target(this.link, this.path, this.readingOrderIndex, this.fragment);

  final Link link;
  final String path;
  final int? readingOrderIndex;
  final String? fragment;
}

final class _TocEntry {
  const _TocEntry(this.title, this.readingOrderIndex, this.fragment);

  final String title;
  final int readingOrderIndex;
  final String? fragment;
}

const _textTypes = {'application/xhtml+xml', 'text/html', 'image/svg+xml'};

/// Reading services for a publication: document text, locators, CFI
/// resolution, positions and search.
///
/// All services derive from [DocumentText], so locations do not depend on a
/// renderer's pixels. Parsed documents are kept in a small least-recently-used
/// cache. The caller owns [publication]; services fail with a
/// [ResourceException] after it is closed.
///
/// Locators include `position` and `totalProgression` once [positions] has
/// completed; computing positions parses every reading-order document, so
/// applications usually compute them once and cache
/// [PublicationPositions.toJson].
final class ReadingServices implements SearchService {
  /// Creates reading services for [publication].
  ///
  /// [cacheSize] bounds the number of parsed documents held in memory.
  /// [positions] may supply positions cached earlier for the same
  /// publication; they must match its reading order and
  /// [charactersPerPosition].
  ReadingServices(
    this.publication, {
    this.limits = const ContentLimits(),
    int cacheSize = 8,
    this.charactersPerPosition = 1024,
    this.contextLength = 40,
    PublicationPositions? positions,
  }) : _cacheSize = cacheSize {
    checkContentLimits(limits.maxBytes, limits.maxElements, limits.maxDepth);
    if (cacheSize < 1 || charactersPerPosition < 1 || contextLength < 0) {
      throw ArgumentError('Reading service limits must be positive.');
    }
    final readingOrder = publication.readingOrder;
    for (var i = 0; i < readingOrder.length; i++) {
      final path = _pathOf(readingOrder[i].href);
      if (path == null) continue;
      _readingOrderIndex.putIfAbsent(path, () => i);
      _links.putIfAbsent(path, () => readingOrder[i]);
    }
    for (final link in publication.resources) {
      final path = _pathOf(link.href);
      if (path != null) _links.putIfAbsent(path, () => link);
    }
    // A reading-order item that a browser cannot display, or that is missing,
    // is represented by its manifest fallback, as a reading system shows it.
    final epub = publication is EpubPublication ? publication as EpubPublication : null;
    for (var i = 0; i < readingOrder.length; i++) {
      final link = readingOrder[i];
      final content =
          epub?.fallbackFor(
            link,
            (item) => displayableContentTypes.contains(item.type),
          ) ??
          link;
      _content.add(content);
      final path = identical(content, link) ? null : _pathOf(content.href);
      if (path != null) _substitutes.putIfAbsent(path, () => i);
    }
    if (positions != null) {
      if (!positions._matches(_content, charactersPerPosition)) {
        throw ArgumentError.value(
          positions,
          'positions',
          'Cached positions do not match this publication.',
        );
      }
      _positionsValue = positions;
      _positions = Future.value(positions);
    }
  }

  /// The publication whose resources are read.
  final Publication publication;

  /// Limits applied to each parsed content document.
  final ContentLimits limits;

  /// The number of text code units per reflowable position.
  final int charactersPerPosition;

  /// The number of text code units of context stored in locators.
  final int contextLength;

  final int _cacheSize;
  final Map<String, int> _readingOrderIndex = {};
  final Map<String, Link> _links = {};
  final List<Link> _content = [];
  final Map<String, int> _substitutes = {};
  final LinkedHashMap<String, Future<DocumentText?>> _cache = LinkedHashMap();
  Future<PublicationPositions>? _positions;
  PublicationPositions? _positionsValue;

  /// Returns the reading text of the resource referenced by [link].
  ///
  /// Returns null for resources that are not XHTML, HTML or SVG. Throws a
  /// [ResourceException] when [link] is not a publication resource or cannot
  /// be read, and a [ContentException] when the document is malformed or
  /// exceeds [limits].
  Future<DocumentText?> documentText(Link link) async => _load(_requireTarget(link));

  /// Computes, or returns previously computed, publication positions.
  ///
  /// Documents that are malformed or exceed [limits] receive one position
  /// and are listed in [PublicationPositions.unreadable]; resource access
  /// failures are reported as errors.
  Future<PublicationPositions> positions() => _positions ??= _computePositions().then(
    (value) => _positionsValue = value,
    onError: (Object error, StackTrace stackTrace) {
      _positions = null;
      Error.throwWithStackTrace(error, stackTrace);
    },
  );

  /// Returns a locator for a navigation or resource [link], without reading
  /// the resource.
  ///
  /// A link fragment becomes [Locations.fragments]; a link without one is
  /// located at progression 0. Returns null for links outside the
  /// publication, such as remote or structural navigation entries.
  Locator? locatorFromLink(Link link) {
    final target = _target(link.href);
    if (target == null) return null;
    final fragment = target.fragment;
    return Locator(
      href: target.link.href,
      type: _type(target.link),
      title: link.title ?? target.link.title,
      locations: Locations(
        fragments: [?fragment],
        progression: fragment == null ? 0 : null,
      ),
    );
  }

  /// Returns a locator for [cfi].
  ///
  /// Without [link], [cfi] must be a publication CFI whose package path
  /// references a spine item of an EPUB publication. With [link], [cfi] is a
  /// content-document CFI for that resource, such as a renderer selection. A
  /// range CFI produces a locator whose highlight is the range text. Returns
  /// null when the CFI does not resolve.
  Future<Locator?> locatorForCfi(EpubCfi cfi, {Link? link}) async {
    _Target? target;
    EpubCfi? content = cfi;
    if (link == null) {
      final split = _splitPublicationCfi(cfi);
      if (split == null) return null;
      target = _target(split.$1.link.href);
      content = split.$2;
    } else {
      target = _target(link.href);
    }
    if (target == null) return null;
    final document = await _load(target);
    if (document == null || content == null) {
      return _locator(target, document, 0, 0, cfi: content?.start);
    }
    final range = document.resolveCfi(content);
    if (range == null) return null;
    return _locator(
      target,
      document,
      range.start,
      range.end,
      cfi: range.match == CfiMatch.exact ? content.start : null,
    );
  }

  /// Returns a locator at [progression] within the resource of [link], such
  /// as a renderer's scroll progression.
  ///
  /// The locator keeps [progression] and adds the CFI and text of the nearest
  /// text offset.
  Future<Locator> locatorForProgression(Link link, double progression) async {
    if (!progression.isFinite || progression < 0 || progression > 1) {
      throw ArgumentError.value(progression, 'progression', 'Must be from 0 to 1.');
    }
    final target = _requireTarget(link);
    final document = await _load(target);
    final offset = ((document?.length ?? 0) * progression).round();
    return _locator(target, document, offset, offset, progression: progression);
  }

  /// Returns a locator for the text range from [start] to [end] in the
  /// resource of [link], such as a hit from an application's search index.
  ///
  /// Offsets refer to that resource's [DocumentText.text]. Throws an
  /// [ArgumentError] for a resource without text.
  Future<Locator> locatorForTextRange(Link link, int start, int end) async {
    final target = _requireTarget(link);
    final document = await _load(target);
    if (document == null) {
      throw ArgumentError.value(link.href, 'link', 'Resource has no text.');
    }
    RangeError.checkValidRange(start, end, document.length);
    return _locator(target, document, start, end);
  }

  /// Returns the publication CFI for a content-document [contentCfi] in the
  /// resource of [link], or null when the publication is not an EPUB or the
  /// resource is not a spine item.
  EpubCfi? publicationCfi(Link link, EpubCfi contentCfi) {
    final target = _target(link.href);
    if (target == null) return null;
    final index = target.readingOrderIndex;
    final item = _spineItem(
      index == null
          ? target.path
          : _pathOf(publication.readingOrder[index].href) ?? target.path,
    );
    if (item == null) return null;
    final parent = contentCfi.path.steps;
    final path = CfiPath([
      ...item.cfiPath.steps,
      parent.first.withIndirect(true),
      ...parent.skip(1),
    ], offset: contentCfi.path.offset);
    return contentCfi.isRange
        ? EpubCfi.range(path, contentCfi.rangeStart!, contentCfi.rangeEnd!)
        : EpubCfi(path);
  }

  /// Resolves a stored [locator] against the current publication content.
  ///
  /// Representations are tried from most to least precise: the
  /// content-document CFI when it resolves and agrees with the locator text,
  /// the locator text nearest to the other estimates, fragment identifiers,
  /// progression, position and finally the resource start. Returns null when
  /// [Locator.href] is not a publication resource.
  Future<LocatorResolution?> resolve(Locator locator) async {
    final target = _target(locator.href);
    if (target == null) return null;
    final document = await _load(target);
    final locations = locator.locations;
    LocatorResolution result(int start, int end, LocatorMatch match, {EpubCfi? cfi}) {
      final length = document?.length ?? 0;
      final from = start.clamp(0, length);
      final to = end.clamp(from, length);
      final content = document == null ? cfi : (cfi ?? document.cfiForRange(from, to));
      final refreshed = _locator(
        target,
        document,
        from,
        to,
        cfi: content?.start,
        fragments: locations.fragments,
        extensions: locations.otherLocations,
        progression: document == null ? locations.progression : null,
      );
      return LocatorResolution._(
        locator: refreshed,
        link: target.link,
        readingOrderIndex: target.readingOrderIndex,
        start: from,
        end: to,
        contentCfi: content,
        cfi: content == null ? null : publicationCfi(target.link, content),
        match: match,
      );
    }

    if (document == null) {
      final partial = locations.partialCfi;
      return result(
        0,
        0,
        locations.progression != null ? LocatorMatch.progression : LocatorMatch.start,
        cfi: partial == null ? null : EpubCfi.tryParse(partial),
      );
    }
    final text = locator.text;
    final highlight = text.highlight;
    CfiTextRange? located;
    if (locations.partialCfi case final partial?) {
      final cfi = EpubCfi.tryParse(partial);
      located = cfi == null ? null : document.resolveCfi(cfi);
      if (located != null &&
          located.match != CfiMatch.approximate &&
          _textAgrees(document, located.start, text)) {
        final end = highlight == null
            ? located.end
            : max(located.end, located.start + highlight.length);
        return result(
          located.start,
          end,
          LocatorMatch.cfi,
          cfi: located.match == CfiMatch.exact && end == located.end ? cfi : null,
        );
      }
    }
    final estimate =
        located?.start ??
        (locations.progression == null
            ? null
            : (locations.progression! * document.length).round()) ??
        _offsetForPosition(target, locations.position) ??
        0;
    if (_findText(document, text, estimate) case (final start, final end)) {
      return result(start, end, LocatorMatch.text);
    }
    if (located != null) {
      return result(located.start, located.end, LocatorMatch.cfi);
    }
    for (final fragment in locations.fragments) {
      final offset = document.offsetOfId(fragment);
      if (offset != null) return result(offset, offset, LocatorMatch.fragment);
    }
    if (locations.progression case final progression?) {
      final offset = (progression * document.length).round();
      return result(offset, offset, LocatorMatch.progression);
    }
    if (_offsetForPosition(target, locations.position) case final offset?) {
      return result(offset, offset, LocatorMatch.position);
    }
    return result(0, 0, LocatorMatch.start);
  }

  /// Searches reading-order documents lazily, one document at a time.
  ///
  /// Matches never span text blocks. Results include `position` and
  /// `totalProgression` once [positions] has completed.
  @override
  Stream<SearchResult> search(
    String query, {
    SearchOptions options = const SearchOptions(),
  }) async* {
    final matcher = SearchMatcher(query, options);
    if (matcher.query.isEmpty) return;
    var count = 0;
    final readingOrder = publication.readingOrder;
    for (var i = 0; i < readingOrder.length; i++) {
      final target = _target(readingOrder[i].href);
      if (target == null || !_textTypes.contains(target.link.type)) continue;
      final DocumentText? document;
      try {
        document = await _load(target);
      } on ContentException {
        if (options.skipUnreadable) continue;
        rethrow;
      }
      if (document == null) continue;
      for (final block in document.blocks) {
        for (final (start, end) in matcher.matches(block.text)) {
          final from = block.start + start;
          final to = block.start + end;
          yield SearchResult(
            locator: _locator(
              target,
              document,
              from,
              to,
              context: options.contextLength,
            ),
            readingOrderIndex: i,
            cfi: publicationCfi(target.link, document.cfiForRange(from, to)),
          );
          if (++count >= options.maxResults) return;
        }
      }
    }
  }

  Future<DocumentText?> _load(_Target target) {
    final type = target.link.type;
    if (!_textTypes.contains(type)) return Future.value();
    final cached = _cache.remove(target.path);
    if (cached != null) {
      _cache[target.path] = cached;
      return cached;
    }
    // Failures are not cached, so a later request can retry.
    late final Future<DocumentText?> future;
    future = _read(target, type!).then(
      (document) => document,
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_cache[target.path], future)) _cache.remove(target.path);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _cache[target.path] = future;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  Future<DocumentText?> _read(_Target target, String type) async {
    final resource = publication.resource(target.link);
    final length = await resource.length;
    if (length != null && length > limits.maxBytes) {
      throw ContentException('Content document exceeds byte limit.', path: target.path);
    }
    return DocumentText.decode(
      await resource.read(),
      mediaType: type,
      limits: limits,
      path: target.path,
    );
  }

  Future<PublicationPositions> _computePositions() async {
    final readingOrder = publication.readingOrder;
    final perPosition = charactersPerPosition;
    final resources = <_PositionResource>[];
    final pending = <(String?, String?)>[];
    var start = 1;
    for (var i = 0; i < readingOrder.length; i++) {
      final link = readingOrder[i];
      final target = _target(link.href);
      DocumentText? document;
      var unreadable = false;
      if (target != null && !_isFixed(link)) {
        try {
          document = await _load(target);
        } on ContentException {
          unreadable = true;
        }
      }
      final length = document?.length;
      final count = length == null || length == 0
          ? 1
          : (length + perPosition - 1) ~/ perPosition;
      for (var k = 0; k < count; k++) {
        final offset = min(k * perPosition, length ?? 0);
        pending.add((
          document?.cfiAt(offset).expression,
          _titleFor(i, offset, document),
        ));
      }
      resources.add(
        _PositionResource(_content[i].href, start, count, length, unreadable),
      );
      start += count;
    }
    final total = start - 1;
    final locators = <Locator>[];
    for (var i = 0; i < resources.length; i++) {
      final resource = resources[i];
      final link = _content[i];
      for (var k = 0; k < resource.count; k++) {
        final (cfi, title) = pending[resource.start - 1 + k];
        final length = resource.length;
        locators.add(
          Locator(
            href: link.href,
            type: _type(link),
            title: title,
            locations: Locations(
              progression: length == null || length == 0
                  ? 0
                  : min(k * perPosition, length) / length,
              position: resource.start + k,
              totalProgression: (resource.start - 1 + k) / total,
              otherLocations: {'partialCfi': ?cfi},
            ),
          ),
        );
      }
    }
    return PublicationPositions._(
      perPosition,
      List.unmodifiable(resources),
      List.unmodifiable(locators),
    );
  }

  Locator _locator(
    _Target target,
    DocumentText? document,
    int start,
    int end, {
    EpubCfi? cfi,
    int? context,
    double? progression,
    List<String> fragments = const [],
    Map<String, Object?> extensions = const {},
  }) {
    final length = document?.length ?? 0;
    var from = start;
    var to = end;
    var partial = cfi;
    if (partial == null && document != null) {
      // Snap to the canonical offset of the generated CFI, so a point between
      // blocks carries text context that agrees with its CFI.
      partial = document.cfiAt(from);
      from = document.resolveCfi(partial)?.start ?? from;
      if (to < from) to = from;
    }
    final index = target.readingOrderIndex;
    int? position;
    double? totalProgression;
    final positions = _positionsValue;
    if (positions != null && index != null) {
      (position, totalProgression) = positions._atOffset(index, from, length);
    }
    return Locator(
      href: target.link.href,
      type: _type(target.link),
      title: index == null ? target.link.title : _titleFor(index, from, document),
      locations: Locations(
        fragments: fragments,
        progression: progression ?? (length == 0 ? 0 : from / length),
        position: position,
        totalProgression: totalProgression,
        otherLocations: {
          ...extensions,
          if (partial != null) 'partialCfi': partial.expression,
        },
      ),
      text: document?.textAround(from, to, context: context ?? contextLength),
    );
  }

  _Target _requireTarget(Link link) =>
      _target(link.href) ??
      (throw ResourceException('Link is not a publication resource.', path: link.href));

  _Target? _target(String href) {
    var path = _pathOf(href);
    if (path == null) return null;
    var index = _readingOrderIndex[path];
    var link = _links[path];
    if (link == null) return null;
    final raw = Uri.parse(href).fragment;
    String? fragment;
    if (raw.isNotEmpty) {
      try {
        fragment = Uri.decodeComponent(raw);
      } on ArgumentError {
        fragment = raw;
      }
    }
    if (index != null) {
      final content = _content[index];
      if (!identical(content, publication.readingOrder[index])) {
        // Locations refer to the fallback document a reader displays.
        link = content;
        path = _pathOf(content.href) ?? path;
        fragment = null;
      }
    } else {
      index = _substitutes[path];
    }
    return _Target(link, path, index, fragment);
  }

  String? _pathOf(String href) {
    if (href.isEmpty) return null;
    try {
      final uri = Uri.parse(href);
      if (uri.hasScheme || uri.hasAuthority) return null;
      return resolvePublicationPath(uri);
    } on FormatException {
      return null;
    } on PublicationException {
      return null;
    }
  }

  bool _isFixed(Link link) => switch (link.properties['layout']) {
    'fixed' => true,
    'reflowable' => false,
    _ => publication.metadata.layout == 'fixed',
  };

  String _type(Link link) => link.type ?? 'application/octet-stream';

  late final List<_TocEntry> _toc = () {
    final entries = <_TocEntry>[];
    void visit(List<Link> links) {
      for (final link in links) {
        final title = link.title;
        final target = _target(link.href);
        final index = target?.readingOrderIndex;
        if (title != null && title.isNotEmpty && index != null) {
          entries.add(_TocEntry(title, index, target!.fragment));
        }
        visit(link.children);
      }
    }

    visit(publication.tableOfContents);
    return entries;
  }();

  /// The title of the last table-of-contents entry at or before a location.
  String? _titleFor(int readingOrderIndex, int offset, DocumentText? document) {
    _TocEntry? best;
    var bestIndex = -1;
    var bestOffset = -1;
    for (final entry in _toc) {
      if (entry.readingOrderIndex > readingOrderIndex) continue;
      var entryOffset = -1;
      if (entry.readingOrderIndex == readingOrderIndex) {
        final fragment = entry.fragment;
        entryOffset = fragment == null ? 0 : (document?.offsetOfId(fragment) ?? 0);
        if (entryOffset > offset) continue;
      }
      if (entry.readingOrderIndex > bestIndex ||
          (entry.readingOrderIndex == bestIndex && entryOffset >= bestOffset)) {
        best = entry;
        bestIndex = entry.readingOrderIndex;
        bestOffset = entryOffset;
      }
    }
    return best?.title ?? publication.readingOrder[readingOrderIndex].title;
  }

  int? _offsetForPosition(_Target target, int? position) {
    final positions = _positionsValue;
    final index = target.readingOrderIndex;
    if (positions == null || index == null || position == null) return null;
    final resource = positions._resources[index];
    if (position < resource.start || position >= resource.start + resource.count) {
      return null;
    }
    return (position - resource.start) * positions.charactersPerPosition;
  }

  EpubSpineItem? _spineItem(String path) {
    final publication = this.publication;
    if (publication is! EpubPublication) return null;
    for (final item in publication.spine) {
      if (_pathOf(item.link.href) == path) return item;
    }
    return null;
  }

  /// Splits a publication CFI into its spine item and content-document CFI.
  (EpubSpineItem, EpubCfi?)? _splitPublicationCfi(EpubCfi cfi) {
    final publication = this.publication;
    if (publication is! EpubPublication || publication.spine.isEmpty) return null;
    final steps = cfi.path.steps;
    final indirection = steps.indexWhere((step) => step.indirect);
    if (indirection < 0 && cfi.isRange) {
      // The indirection is inside the local paths; use the range start.
      return _splitPublicationCfi(cfi.start);
    }
    final package = indirection < 0 ? steps : steps.sublist(0, indirection);
    if (package.length != 2 ||
        package.first.index != publication.spine.first.cfiPath.steps.first.index) {
      return null;
    }
    final item = _itemFor(publication.spine, package[1]);
    if (item == null) return null;
    if (indirection < 0) return (item, null);
    final content = CfiPath([
      steps[indirection].withIndirect(false),
      ...steps.skip(indirection + 1),
    ], offset: cfi.path.offset);
    try {
      return (
        item,
        cfi.isRange
            ? EpubCfi.range(content, cfi.rangeStart!, cfi.rangeEnd!)
            : EpubCfi(content),
      );
    } on ArgumentError {
      return null;
    }
  }

  /// Finds the spine item of an itemref step, correcting it by its ID
  /// assertion. Manifest IDs are also accepted as assertions, as some
  /// reading systems write them.
  EpubSpineItem? _itemFor(List<EpubSpineItem> spine, CfiStep step) {
    EpubSpineItem? atIndex;
    for (final item in spine) {
      if (item.cfiPath.steps.last.index == step.index) atIndex = item;
    }
    final id = step.id;
    if (id == null || atIndex?.cfiPath.steps.last.id == id) return atIndex;
    for (final item in spine) {
      if (item.cfiPath.steps.last.id == id) return item;
    }
    for (final item in spine) {
      if (item.idref == id) return item;
    }
    return null;
  }
}

/// Whether locator text agrees with the document at [offset], ignoring
/// differences in whitespace such as block separators at the join.
bool _textAgrees(DocumentText document, int offset, LocatorText text) {
  String normal(String value) => value.replaceAll(RegExp(r'\s+'), ' ');
  final content = document.text;
  String window(int from, int to) =>
      normal(content.substring(max(0, from), min(content.length, to)));
  if (text.highlight case final highlight?) {
    final target = normal(highlight).trim();
    return window(
      offset,
      offset + 2 * highlight.length + 8,
    ).trimLeft().startsWith(target);
  }
  if (text.before case final before?) {
    final target = normal(before).trim();
    if (!window(offset - 2 * before.length - 8, offset).trimRight().endsWith(target)) {
      return false;
    }
  }
  if (text.after case final after?) {
    final target = normal(after).trim();
    if (!window(offset, offset + 2 * after.length + 8).trimLeft().startsWith(target)) {
      return false;
    }
  }
  return true;
}

/// Finds locator text nearest to [estimate], trying the most specific
/// combination of context and highlight first.
(int, int)? _findText(DocumentText document, LocatorText text, int estimate) {
  String normal(String? value) => (value ?? '').replaceAll('\n', ' ');
  final before = normal(text.before);
  final highlight = normal(text.highlight);
  final after = normal(text.after);
  final candidates = highlight.isNotEmpty
      ? [
          ('$before$highlight$after', before.length),
          ('$highlight$after', 0),
          ('$before$highlight', before.length),
          (highlight, 0),
        ]
      : [('$before$after', before.length), (before, before.length), (after, 0)];
  final haystack = document.text.replaceAll('\n', ' ');
  for (final (needle, lead) in candidates) {
    if (needle.trim().isEmpty) continue;
    int? best;
    var scanned = 0;
    for (
      var index = haystack.indexOf(needle);
      index >= 0 && scanned < 10000;
      index = haystack.indexOf(needle, index + 1), scanned++
    ) {
      final candidate = index + lead;
      if (best == null || (candidate - estimate).abs() < (best - estimate).abs()) {
        best = candidate;
      }
    }
    if (best != null) return (best, best + highlight.length);
  }
  return null;
}
