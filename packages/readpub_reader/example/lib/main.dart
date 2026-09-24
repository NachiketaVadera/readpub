import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:readpub/readpub.dart';
import 'package:readpub_reader/readpub_reader.dart';

void main() => runApp(const ReaderApp());

/// The decoration group holding the reader's highlights.
const highlightGroup = 'highlights';

/// The highlight styles offered by the example.
const highlightStyles = [
  ReaderDecorationStyle.highlight(),
  ReaderDecorationStyle.highlight(Color(0x7081c784)),
  ReaderDecorationStyle.highlight(Color(0x7064b5f6)),
  ReaderDecorationStyle.highlight(Color(0x70f48fb1)),
  ReaderDecorationStyle.underline(),
];

/// The example application.
class ReaderApp extends StatelessWidget {
  /// Creates the application.
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'readpub reader',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const BookScreen(asset: 'assets/lantern-keeper.epub'),
  );
}

/// Reads a bundled EPUB.
class BookScreen extends StatefulWidget {
  /// Creates a screen for the EPUB asset at [asset].
  const BookScreen({super.key, required this.asset});

  /// The asset key of the EPUB to open.
  final String asset;

  @override
  State<BookScreen> createState() => BookScreenState();
}

/// The state of [BookScreen], exposed for integration tests.
class BookScreenState extends State<BookScreen> {
  EpubPublication? _book;
  ReaderController? _controller;
  Object? _error;
  bool _chrome = true;
  final List<Locator> _bookmarks = [];
  final List<ReaderDecoration> _highlights = [];
  int _nextHighlight = 0;

  /// The reader controller, once the book is open.
  ReaderController? get controller => _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final data = await rootBundle.load(widget.asset);
      final book = await EpubPublication.open(
        MemoryAsset(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
      final controller =
          await ReaderController.create(
              book,
              settings: ReaderSettings(flow: ReaderFlow.paged),
              onExternalLink: _external,
            )
            ..onDecorationActivated = _highlightTapped;
      if (!mounted) {
        controller.dispose();
        await book.close();
        return;
      }
      setState(() {
        _book = book;
        _controller = controller;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_book?.close());
    super.dispose();
  }

  void _external(Uri url) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('External link'),
          content: Text('This link leaves the book:\n$url'),
          actions: [
            TextButton(
              onPressed: () {
                unawaited(
                  Clipboard.setData(ClipboardData(text: url.toString())),
                );
                Navigator.pop(context);
              },
              child: const Text('Copy link'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _highlight(ReaderController controller) async {
    // The locator captured with the selection; a tap outside the page may
    // already have cleared the page's selection.
    final locator = controller.selection?.locator;
    if (locator == null) return;
    setState(
      () => _highlights.add(
        ReaderDecoration(id: '${_nextHighlight++}', locator: locator),
      ),
    );
    await controller.applyDecorations(highlightGroup, _highlights);
    await controller.clearSelection();
  }

  void _highlightTapped(ReaderDecorationActivation activation) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => _HighlightSheet(
          highlight: activation.decoration,
          onStyle: (style) {
            final index = _highlights.indexWhere(
              (h) => h.id == activation.decoration.id,
            );
            if (index < 0) return;
            setState(
              () => _highlights[index] = ReaderDecoration(
                id: activation.decoration.id,
                locator: activation.decoration.locator,
                style: style,
              ),
            );
            unawaited(controller.applyDecorations(highlightGroup, _highlights));
          },
          onDelete: () {
            setState(
              () => _highlights.removeWhere(
                (h) => h.id == activation.decoration.id,
              ),
            );
            unawaited(controller.applyDecorations(highlightGroup, _highlights));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text('$_error'),
        ),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: _chrome ? _appBar(controller) : null,
        drawer: _Contents(
          controller: controller,
          bookmarks: _bookmarks,
          highlights: _highlights,
        ),
        body: SafeArea(
          child: ReaderView(
            controller: controller,
            onCenterTap: () => setState(() => _chrome = !_chrome),
          ),
        ),
        bottomNavigationBar: _chrome ? _Progress(controller: controller) : null,
        // A floating button does not resize the page while text is selected.
        floatingActionButton: controller.selection == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => unawaited(_highlight(controller)),
                icon: const Icon(Icons.border_color),
                label: const Text('Highlight'),
              ),
      ),
    );
  }

  PreferredSizeWidget _appBar(ReaderController controller) => AppBar(
    title: Text(controller.publication.metadata.title),
    actions: [
      IconButton(
        tooltip: 'Search',
        icon: const Icon(Icons.search),
        onPressed: () => unawaited(_search(controller)),
      ),
      IconButton(
        tooltip: 'Bookmark',
        icon: const Icon(Icons.bookmark_add_outlined),
        onPressed: controller.location == null
            ? null
            : () {
                setState(() => _bookmarks.add(controller.location!.locator));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Bookmark added')));
              },
      ),
      IconButton(
        tooltip: 'Display settings',
        icon: const Icon(Icons.text_format),
        onPressed: () => unawaited(
          showModalBottomSheet<void>(
            context: context,
            builder: (context) => _Settings(controller: controller),
          ),
        ),
      ),
    ],
  );

  Future<void> _search(ReaderController controller) async {
    final locator = await Navigator.push<Locator>(
      context,
      MaterialPageRoute(
        builder: (context) => _SearchScreen(controller: controller),
      ),
    );
    if (locator != null) await controller.go(locator);
  }
}

class _Contents extends StatelessWidget {
  const _Contents({
    required this.controller,
    required this.bookmarks,
    required this.highlights,
  });

  final ReaderController controller;
  final List<Locator> bookmarks;
  final List<ReaderDecoration> highlights;

  @override
  Widget build(BuildContext context) {
    final entries = <Widget>[];
    void add(List<Link> links, int depth) {
      for (final link in links) {
        entries.add(
          ListTile(
            contentPadding: EdgeInsetsDirectional.only(
              start: 16 + depth * 16.0,
              end: 16,
            ),
            title: Text(link.title ?? link.href),
            onTap: () {
              Navigator.pop(context);
              unawaited(controller.goToLink(link));
            },
          ),
        );
        add(link.children, depth + 1);
      }
    }

    add(controller.publication.tableOfContents, 0);
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text(
                'Contents',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...entries,
            if (bookmarks.isNotEmpty) ...[
              const Divider(),
              const ListTile(
                title: Text(
                  'Bookmarks',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final bookmark in bookmarks)
                ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: Text(bookmark.title ?? bookmark.href),
                  subtitle: Text(
                    (bookmark.text.after ?? '').trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(controller.go(bookmark));
                  },
                ),
            ],
            if (highlights.isNotEmpty) ...[
              const Divider(),
              const ListTile(
                title: Text(
                  'Highlights',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final highlight in highlights)
                ListTile(
                  leading: Icon(
                    highlight.style.kind == ReaderDecorationKind.underline
                        ? Icons.format_underlined
                        : Icons.border_color,
                    color: highlight.style.color.withValues(alpha: 1),
                  ),
                  title: Text(
                    (highlight.locator.text.highlight ?? '').trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(highlight.locator.title ?? ''),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(controller.go(highlight.locator));
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final location = controller.location;
    final positions = controller.positions;
    final locations = location?.locator.locations;
    final position = locations?.position;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (positions != null && position != null)
              Slider(
                value: position.toDouble(),
                min: 1,
                max: positions.total.toDouble(),
                divisions: positions.total > 1 ? positions.total - 1 : null,
                label: 'Position $position',
                onChanged: (_) {},
                onChangeEnd: (value) => unawaited(
                  controller.go(positions.locators[value.round() - 1]),
                ),
              ),
            Text(
              [
                location?.locator.title ?? '',
                if (location != null && location.pageCount > 1)
                  'page ${location.page + 1} of ${location.pageCount}',
                if (locations?.totalProgression != null)
                  '${(locations!.totalProgression! * 100).round()}%',
              ].where((part) => part.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Settings extends StatefulWidget {
  const _Settings({required this.controller});

  final ReaderController controller;

  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  late ReaderSettings _settings = widget.controller.settings;

  void _apply(ReaderSettings settings) {
    setState(() => _settings = settings);
    unawaited(widget.controller.updateSettings(settings));
  }

  ReaderSettings _copy({
    ReaderTheme? theme,
    double? fontScale,
    ReaderFlow? flow,
  }) => ReaderSettings(
    theme: theme ?? _settings.theme,
    fontScale: fontScale ?? _settings.fontScale,
    flow: flow ?? _settings.flow,
    lineHeight: _settings.lineHeight,
    margin: _settings.margin,
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ReaderTheme>(
            segments: const [
              ButtonSegment(value: ReaderTheme.light, label: Text('Light')),
              ButtonSegment(value: ReaderTheme.sepia, label: Text('Sepia')),
              ButtonSegment(value: ReaderTheme.dark, label: Text('Dark')),
            ],
            selected: {_settings.theme},
            onSelectionChanged: (value) => _apply(_copy(theme: value.single)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.text_decrease),
              Expanded(
                child: Slider(
                  value: _settings.fontScale,
                  min: 0.8,
                  max: 2,
                  divisions: 12,
                  onChanged: (value) =>
                      setState(() => _settings = _copy(fontScale: value)),
                  onChangeEnd: (value) => _apply(_copy(fontScale: value)),
                ),
              ),
              const Icon(Icons.text_increase),
            ],
          ),
          SwitchListTile(
            title: const Text('Paginated'),
            value: _settings.flow == ReaderFlow.paged,
            onChanged: (paged) => _apply(
              _copy(flow: paged ? ReaderFlow.paged : ReaderFlow.scroll),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SearchScreen extends StatefulWidget {
  const _SearchScreen({required this.controller});

  final ReaderController controller;

  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen> {
  List<SearchResult> _results = const [];
  bool _searching = false;

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    final results = await widget.controller.services
        .search(query, options: const SearchOptions(maxResults: 200))
        .toList();
    if (mounted) {
      setState(() {
        _results = results;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Search the book'),
        textInputAction: TextInputAction.search,
        onSubmitted: (query) => unawaited(_search(query)),
      ),
    ),
    body: _searching
        ? const Center(child: CircularProgressIndicator())
        : ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final locator = _results[index].locator;
              final text = locator.text;
              return ListTile(
                title: Text(locator.title ?? locator.href),
                subtitle: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '…${(text.before ?? '').replaceAll('\n', ' ')}',
                      ),
                      TextSpan(
                        text: text.highlight,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: '${(text.after ?? '').replaceAll('\n', ' ')}…',
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, locator),
              );
            },
          ),
  );
}

class _HighlightSheet extends StatelessWidget {
  const _HighlightSheet({
    required this.highlight,
    required this.onStyle,
    required this.onDelete,
  });

  final ReaderDecoration highlight;
  final ValueChanged<ReaderDecorationStyle> onStyle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '“${(highlight.locator.text.highlight ?? '').trim()}”',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final style in highlightStyles)
                IconButton(
                  tooltip: style.kind == ReaderDecorationKind.underline
                      ? 'Underline'
                      : 'Highlight color',
                  isSelected: style == highlight.style,
                  icon: Icon(
                    style.kind == ReaderDecorationKind.underline
                        ? Icons.format_underlined
                        : Icons.circle,
                    color: style.color.withValues(alpha: 1),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    onStyle(style);
                  },
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Remove highlight',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
