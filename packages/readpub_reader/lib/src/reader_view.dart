import 'dart:async';

import 'package:flutter/material.dart';
import 'package:readpub/readpub.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'reader_controller.dart';
import 'reader_surface.dart';

/// Displays the publication driven by a [ReaderController].
///
/// Taps near the leading and trailing edges turn pages, mirrored for
/// right-to-left publications; other taps call [onCenterTap]. Swipes in paged
/// flow and arrow keys also turn pages. The page is covered until the
/// controller has positioned the loaded chapter.
class ReaderView extends StatefulWidget {
  /// Creates a reader view.
  ///
  /// The controller's surface must be a [WebViewReaderSurface].
  const ReaderView({
    super.key,
    required this.controller,
    this.onCenterTap,
    this.edgeTapFraction = 0.25,
    this.loadingBuilder,
  }) : assert(edgeTapFraction >= 0 && edgeTapFraction <= 0.5);

  /// The controller supplying chapters and locations.
  final ReaderController controller;

  /// Called for taps outside the page-turning edges and links.
  final VoidCallback? onCenterTap;

  /// The fraction of the width at each edge that turns pages.
  final double edgeTapFraction;

  /// Builds the cover shown while a chapter loads; a progress indicator by
  /// default.
  final WidgetBuilder? loadingBuilder;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(ReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    super.dispose();
  }

  void _attach(ReaderController controller) {
    controller.addListener(_changed);
    controller.onTap = _tap;
  }

  void _detach(ReaderController controller) {
    controller.removeListener(_changed);
    if (controller.onTap == _tap) controller.onTap = null;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _tap(double x, double y) {
    final controller = widget.controller;
    final edge = widget.edgeTapFraction;
    final leading = controller.isRightToLeft ? x > 1 - edge : x < edge;
    final trailing = controller.isRightToLeft ? x < edge : x > 1 - edge;
    if (leading) {
      unawaited(controller.previousPage());
    } else if (trailing) {
      unawaited(controller.nextPage());
    } else {
      widget.onCenterTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final surface = controller.surface;
    if (surface is! WebViewReaderSurface) {
      throw FlutterError('ReaderView requires a WebViewReaderSurface.');
    }
    final background = switch (controller.settings.theme) {
      ReaderTheme.light => const Color(0xffffffff),
      ReaderTheme.dark => const Color(0xff17191c),
      ReaderTheme.sepia => const Color(0xfff4ecd8),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: surface.webViewController),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: controller.isReady ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: ColoredBox(
              color: background,
              child:
                  widget.loadingBuilder?.call(context) ??
                  const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ],
    );
  }
}
