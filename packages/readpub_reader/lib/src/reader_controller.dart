import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color, Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:readpub/readpub.dart';

import 'bridge_script.dart';
import 'decoration_script.dart';
import 'reader_decoration.dart';
import 'reader_surface.dart';

/// The displayed reading location.
@immutable
final class ReaderLocation {
  /// Creates a reading location.
  const ReaderLocation({
    required this.locator,
    required this.readingOrderIndex,
    required this.page,
    required this.pageCount,
  });

  /// A persistable locator for the first visible character.
  final Locator locator;

  /// The reading-order index of the displayed resource, or null for a
  /// resource outside the reading order, such as a linked note.
  final int? readingOrderIndex;

  /// The zero-based page within the resource; 0 in scroll flow.
  final int page;

  /// The number of pages in the resource; 1 in scroll flow.
  final int pageCount;
}

/// The currently selected text.
@immutable
final class ReaderSelection {
  /// Creates a selection.
  const ReaderSelection({required this.text, required this.locator});

  /// The selected text.
  final String text;

  /// A locator whose `text.highlight` is the selection.
  final Locator locator;
}

/// A direction of travel through the publication.
enum ReaderDirection {
  /// Toward the end of the publication.
  forward,

  /// Toward the start of the publication.
  backward,
}

/// Drives an EPUB reader: navigation, pages, settings and locations.
///
/// The controller starts an `EpubRenderSession` and `ReadingServices` for a
/// publication owned by the caller, loads chapters into a [ReaderSurface] and
/// injects `readerLocationScript`, [readerBridgeScript] and
/// [readerDecorationScript] into each. Every reading location is reported as
/// a [ReaderLocation] with a persistable [Locator]; restore it with [go].
/// Highlights and other [ReaderDecoration]s are drawn with
/// [applyDecorations]. Dispose the controller before closing the
/// publication.
final class ReaderController extends ChangeNotifier {
  ReaderController._(
    this.publication,
    this.session,
    this.services,
    this.surface,
  );

  /// Starts reading [publication] at [initialLocator], or at the start.
  ///
  /// [positions] may supply positions cached earlier; otherwise they are
  /// computed in the background and later locations include them.
  /// [onExternalLink] receives links leaving the publication, which are never
  /// opened by the surface.
  static Future<ReaderController> create(
    EpubPublication publication, {
    ReaderSettings? settings,
    Locator? initialLocator,
    PublicationPositions? positions,
    ReaderSurface? surface,
    void Function(Uri url)? onExternalLink,
  }) async {
    final session = await EpubRenderSession.start(
      publication,
      settings: settings,
    );
    final services = ReadingServices(publication, positions: positions);
    final controller = ReaderController._(
      publication,
      session,
      services,
      surface ?? WebViewReaderSurface(),
    );
    controller.onExternalLink = onExternalLink;
    controller._attach();
    unawaited(controller._computePositions());
    if (initialLocator == null || !await controller.go(initialLocator)) {
      await controller._show(
        0,
        publication.readingOrder.first,
        const _Target(),
      );
    }
    return controller;
  }

  /// The publication being read; the caller owns and closes it.
  final EpubPublication publication;

  /// The loopback session that serves prepared chapters.
  final EpubRenderSession session;

  /// Text, locator, position and search services for [publication].
  final ReadingServices services;

  /// The browser surface displaying chapters.
  final ReaderSurface surface;

  /// Receives links that leave the publication, such as web and mail links.
  void Function(Uri url)? onExternalLink;

  /// Receives taps outside links and decorations, with the tap position as
  /// fractions of the surface width and height.
  void Function(double x, double y)? onTap;

  /// Receives taps on drawn decorations.
  void Function(ReaderDecorationActivation activation)? onDecorationActivated;

  ReaderLocation? _location;
  ReaderSelection? _selection;
  PublicationPositions? _positions;
  int? _index;
  Link? _link;
  Uri? _displayed;
  Uri? _loading;
  _Target? _pending;
  bool _ready = false;
  bool _disposed = false;
  int _generation = 0;
  // Identifies the document in the surface; it changes when a load starts
  // and when a document finishes loading.
  int _document = 0;
  // The document into which the decoration script was injected.
  int? _decorated;
  final Map<String, List<ReaderDecoration>> _decorations = {};
  final Map<String, int> _revisions = {};

  /// The displayed location, once the first chapter is positioned.
  ReaderLocation? get location => _location;

  /// The current text selection, if any.
  ReaderSelection? get selection => _selection;

  /// Publication positions, once computed.
  PublicationPositions? get positions => _positions;

  /// Whether a chapter is loaded and positioned.
  bool get isReady => _ready;

  /// The current display settings.
  ReaderSettings get settings => session.settings;

  /// Whether pages turn right to left.
  bool get isRightToLeft => publication.metadata.readingProgression == 'rtl';

  /// Moves to [locator], restoring it from its CFI, text, fragment or
  /// progression. Returns false when it does not identify a resource of the
  /// publication.
  Future<bool> go(Locator locator) async {
    final resolution = await services.resolve(locator);
    if (resolution == null || _disposed) return false;
    final index = resolution.readingOrderIndex;
    final link = index == null
        ? resolution.link
        : publication.readingOrder[index];
    await _show(
      index,
      link,
      _Target(
        cfi: resolution.contentCfi?.start.expression,
        progression: resolution.locator.locations.progression,
      ),
    );
    return true;
  }

  /// Moves to a navigation [link], such as a table of contents entry.
  ///
  /// Returns false for links outside the publication.
  Future<bool> goToLink(Link link) async {
    final locator = services.locatorFromLink(link);
    return locator != null && await go(locator);
  }

  /// Turns to the next page, continuing into the next reading-order item.
  ///
  /// Returns false at the end of the publication.
  Future<bool> nextPage() => _turn(ReaderDirection.forward);

  /// Turns to the previous page, continuing at the end of the previous
  /// reading-order item. Returns false at the start of the publication.
  Future<bool> previousPage() => _turn(ReaderDirection.backward);

  /// Moves to the start of the next reading-order item.
  Future<bool> nextChapter() => _chapter(ReaderDirection.forward, end: false);

  /// Moves to the start of the previous reading-order item.
  Future<bool> previousChapter() =>
      _chapter(ReaderDirection.backward, end: false);

  /// Applies [settings] and restores the current location after relayout.
  Future<void> updateSettings(ReaderSettings settings) async {
    session.updateSettings(settings);
    final link = _link;
    final current = _location?.locator;
    if (link == null) return;
    await _show(
      _index,
      link,
      _Target(
        cfi: current?.locations.partialCfi,
        progression: current?.locations.progression,
      ),
      reload: true,
    );
  }

  /// The decorations applied to [group], in drawing order.
  List<ReaderDecoration> decorations(String group) =>
      _decorations[group] ?? const [];

  /// Replaces the decorations of [group] and draws those in the displayed
  /// resource.
  ///
  /// Groups keep independent sets, such as highlights and search results;
  /// later decorations draw over earlier ones, and groups draw in the order
  /// they were first applied. Decorations in other resources are drawn when
  /// their resource is displayed. Apply an empty list to remove a group.
  /// Throws an [ArgumentError] if two decorations share an id.
  Future<void> applyDecorations(
    String group,
    Iterable<ReaderDecoration> decorations,
  ) async {
    final list = List<ReaderDecoration>.unmodifiable(decorations);
    final ids = <String>{};
    for (final decoration in list) {
      if (!ids.add(decoration.id)) {
        throw ArgumentError.value(
          decoration.id,
          'decorations',
          'Duplicate decoration id in group "$group"',
        );
      }
    }
    if (list.isEmpty) {
      _decorations.remove(group);
    } else {
      _decorations[group] = list;
    }
    _revisions[group] = (_revisions[group] ?? 0) + 1;
    if (!_disposed && _decorated == _document) await _draw([group]);
  }

  /// Clears the text selection in the surface.
  Future<void> clearSelection() async {
    if (_disposed || _decorated != _document) return;
    await surface.run('window.getSelection().removeAllRanges()');
  }

  /// Returns a locator for the current selection, or null without one.
  Future<Locator?> selectionLocator() async {
    final link = _link;
    if (link == null || !_ready) return null;
    final cfi = await surface.evaluate(
      'JSON.stringify(window.readpub.selectionCfi())',
    );
    if (cfi is! String) return null;
    final parsed = EpubCfi.tryParse(cfi);
    return parsed == null ? null : services.locatorForCfi(parsed, link: link);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    surface
      ..onMessage = null
      ..onPageFinished = null
      ..onNavigationRequest = null;
    unawaited(session.close());
    super.dispose();
  }

  void _attach() {
    surface
      ..onMessage = _receive
      ..onPageFinished = (url) {
        unawaited(_pageFinished(url));
      }
      ..onNavigationRequest = _allow;
    unawaited(_setBackground());
  }

  Future<void> _setBackground() async {
    try {
      await surface.setBackgroundColor(_background(session.settings));
    } on UnimplementedError {
      // Some platforms, such as macOS, do not support WebView backgrounds.
    } on UnsupportedError {
      // As above.
    }
  }

  Future<void> _computePositions() async {
    try {
      final positions = await services.positions();
      if (_disposed) return;
      _positions = positions;
      notifyListeners();
      await _relocate();
    } on Object {
      // Locations remain usable without positions.
    }
  }

  bool _allow(Uri url) {
    if (url.toString().startsWith(session.baseUrl.toString())) return true;
    if (url.scheme == 'about') return url.toString() == 'about:blank';
    onExternalLink?.call(url);
    return false;
  }

  Future<void> _show(
    int? index,
    Link link,
    _Target target, {
    bool reload = false,
  }) async {
    // An empty fragment would make reloading the same URL a same-document
    // navigation on Android.
    final url = session.urlFor(link).removeFragment();
    final displayed = _displayed;
    _index = index;
    _link = link;
    if (!reload &&
        _ready &&
        _loading == null &&
        displayed != null &&
        _samePath(url, displayed)) {
      await _restore(target);
      return;
    }
    _pending = target;
    _loading = url;
    _ready = false;
    _generation++;
    _document++;
    notifyListeners();
    await _setBackground();
    if (reload && displayed != null && _samePath(url, displayed)) {
      await surface.reload();
    } else {
      await surface.load(url);
    }
  }

  Future<void> _pageFinished(Uri url) async {
    if (_disposed || !url.toString().startsWith(session.baseUrl.toString())) {
      return;
    }
    _document++;
    final loading = _loading;
    if (loading == null || !_samePath(url, loading)) {
      // A link inside the content navigated to another resource.
      final (index, link) = _resourceFor(url);
      if (link == null) return;
      _index = index;
      _link = link;
      _pending = url.fragment.isEmpty ? const _Target() : null;
    }
    _loading = null;
    _displayed = url;
    final document = _document;
    final target = _pending;
    _pending = null;
    await surface.run(readerLocationScript);
    await surface.run(readerBridgeScript);
    await surface.run(readerDecorationScript);
    if (_disposed) return;
    if (document == _document) {
      _decorated = document;
      // Drawn before positioning, so the page appears with its decorations.
      await _draw(_decorations.keys.toList());
    }
    // A newer load positions its own document.
    if (_disposed || _loading != null) return;
    if (target != null) {
      await _restore(target);
    } else {
      await _relocate();
    }
  }

  Future<void> _restore(_Target target) async {
    final state = await surface.evaluate(
      'window.readpubReader.restore(${jsonEncode(target.toJson())})',
    );
    _ready = true;
    await _applyState(state);
  }

  Future<void> _relocate() async {
    if (_loading != null || _link == null) return;
    final state = await surface.evaluate('window.readpubReader.state()');
    _ready = true;
    await _applyState(state);
  }

  /// Draws the decorations of [groups] that belong to the displayed resource.
  Future<void> _draw(List<String> groups) async {
    final link = _link;
    if (link == null || groups.isEmpty) return;
    final document = _document;
    final revisions = {for (final group in groups) group: _revisions[group]};
    final href = services.locatorFromLink(link)?.href ?? link.href;
    final payload = <String, List<Map<String, Object?>>>{};
    for (final group in groups) {
      final items = <Map<String, Object?>>[];
      for (final decoration in decorations(group)) {
        if (!_sameResource(decoration.locator.href, href)) continue;
        final cfi = await _rangeCfi(decoration.locator);
        if (cfi == null) continue;
        items.add({
          'id': decoration.id,
          'cfi': cfi,
          'style': decoration.style.kind.name,
          'color': _channels(decoration.style.color),
        });
      }
      payload[group] = items;
    }
    for (final MapEntry(key: group, value: items) in payload.entries) {
      // A newer application of the group, or another document, supersedes
      // this drawing.
      if (_disposed ||
          document != _document ||
          _revisions[group] != revisions[group]) {
        continue;
      }
      try {
        await surface.evaluate(
          'window.readpubDecorations.apply('
          '${jsonEncode(group)}, ${jsonEncode(items)})',
        );
      } on Exception {
        // The document changed while drawing; the next document draws again.
      }
    }
  }

  /// A content-document range CFI for the text of [locator], or null when its
  /// text cannot be found.
  Future<String?> _rangeCfi(Locator locator) async {
    final LocatorResolution? resolution;
    try {
      resolution = await services.resolve(locator);
    } on PublicationException {
      return null;
    }
    final cfi = resolution?.contentCfi;
    if (resolution == null ||
        cfi == null ||
        resolution.end <= resolution.start ||
        (resolution.match != LocatorMatch.cfi &&
            resolution.match != LocatorMatch.text)) {
      return null;
    }
    return cfi.expression;
  }

  Future<void> _applyState(Object? state) async {
    final link = _link;
    if (state is! Map || link == null || _disposed) return;
    final generation = _generation;
    final cfi = state['cfi'];
    final progression = state['progression'];
    Locator? locator;
    final parsed = cfi is String ? EpubCfi.tryParse(cfi) : null;
    if (parsed != null) {
      locator = await services.locatorForCfi(parsed, link: link);
    }
    locator ??= await services.locatorForProgression(
      link,
      progression is num ? progression.toDouble().clamp(0, 1).toDouble() : 0,
    );
    if (_disposed || generation != _generation || !identical(link, _link)) {
      return;
    }
    _location = ReaderLocation(
      locator: locator,
      readingOrderIndex: _index,
      page: (state['page'] as num?)?.toInt() ?? 0,
      pageCount: (state['pageCount'] as num?)?.toInt() ?? 1,
    );
    notifyListeners();
  }

  Future<bool> _turn(ReaderDirection direction) async {
    if (!_ready || _disposed) return false;
    final method = direction == ReaderDirection.forward
        ? 'nextPage'
        : 'previousPage';
    final moved = await surface.evaluate('window.readpubReader.$method()');
    if (moved == true) return true;
    return _chapter(direction, end: direction == ReaderDirection.backward);
  }

  Future<bool> _chapter(ReaderDirection direction, {required bool end}) async {
    final current = _index;
    if (current == null) return false;
    final next = current + (direction == ReaderDirection.forward ? 1 : -1);
    if (next < 0 || next >= publication.readingOrder.length) return false;
    await _show(next, publication.readingOrder[next], _Target(end: end));
    return true;
  }

  void _receive(String message) {
    final Object? event;
    try {
      event = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (event is! Map || _disposed) return;
    switch (event['type']) {
      case 'relocated':
        if (_loading == null) unawaited(_applyState(event));
      case 'selection':
        unawaited(_selectionChanged(event['cfi'], event['text']));
      case 'decorationActivated':
        _activated(event);
      case 'tap':
        final x = event['x'];
        final y = event['y'];
        if (x is num && y is num) onTap?.call(x.toDouble(), y.toDouble());
      case 'swipe':
        final left = event['direction'] == 'left';
        unawaited(left != isRightToLeft ? nextPage() : previousPage());
      case 'key':
        switch (event['key']) {
          case 'ArrowRight':
            unawaited(isRightToLeft ? previousPage() : nextPage());
          case 'ArrowLeft':
            unawaited(isRightToLeft ? nextPage() : previousPage());
          case 'PageDown' || ' ':
            unawaited(nextPage());
          case 'PageUp':
            unawaited(previousPage());
        }
    }
  }

  void _activated(Map<Object?, Object?> event) {
    final group = event['group'];
    final id = event['id'];
    final x = event['x'];
    final y = event['y'];
    if (group is! String || id is! String || x is! num || y is! num) return;
    final decoration = decorations(group)
        .where((decoration) => decoration.id == id)
        .firstOrNull;
    if (decoration == null) return;
    final rect = event['rect'];
    onDecorationActivated?.call(
      ReaderDecorationActivation(
        group: group,
        decoration: decoration,
        point: Offset(x.toDouble(), y.toDouble()),
        rect: rect is Map
            ? switch ((rect['x'], rect['y'], rect['width'], rect['height'])) {
                (
                  final num left,
                  final num top,
                  final num width,
                  final num height,
                ) =>
                  Rect.fromLTWH(
                    left.toDouble(),
                    top.toDouble(),
                    width.toDouble(),
                    height.toDouble(),
                  ),
                _ => null,
              }
            : null,
      ),
    );
  }

  Future<void> _selectionChanged(Object? cfi, Object? text) async {
    final link = _link;
    final parsed = cfi is String ? EpubCfi.tryParse(cfi) : null;
    ReaderSelection? selection;
    if (parsed != null && text is String && text.isNotEmpty && link != null) {
      final locator = await services.locatorForCfi(parsed, link: link);
      if (locator != null) {
        selection = ReaderSelection(text: text, locator: locator);
      }
    }
    if (_disposed) return;
    _selection = selection;
    notifyListeners();
  }

  (int?, Link?) _resourceFor(Uri url) {
    final readingOrder = publication.readingOrder;
    for (var i = 0; i < readingOrder.length; i++) {
      if (_samePath(session.urlFor(readingOrder[i]), url)) {
        return (i, readingOrder[i]);
      }
    }
    for (final link in publication.resources) {
      if (!Uri.parse(link.href).hasScheme &&
          _samePath(session.urlFor(link), url)) {
        return (null, link);
      }
    }
    return (null, null);
  }
}

bool _samePath(Uri a, Uri b) => a.path == b.path;

bool _sameResource(String a, String b) {
  if (a == b) return true;
  try {
    return resolvePublicationPath(Uri.parse(a)) ==
        resolvePublicationPath(Uri.parse(b));
  } on FormatException {
    return false;
  } on PublicationException {
    return false;
  }
}

List<num> _channels(Color color) {
  final argb = color.toARGB32();
  return [
    (argb >> 16) & 0xff,
    (argb >> 8) & 0xff,
    argb & 0xff,
    (((argb >> 24) & 0xff) / 255 * 1000).round() / 1000,
  ];
}

Color _background(ReaderSettings settings) => switch (settings.theme) {
  ReaderTheme.light => const Color(0xffffffff),
  ReaderTheme.dark => const Color(0xff17191c),
  ReaderTheme.sepia => const Color(0xfff4ecd8),
};

/// Where to position a chapter once it has loaded.
final class _Target {
  const _Target({this.cfi, this.progression, this.end = false});

  final String? cfi;
  final double? progression;
  final bool end;

  Map<String, Object?> toJson() => {
    'cfi': cfi,
    'progression': progression,
    'end': end,
  };
}
