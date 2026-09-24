/// The way reflowable chapters move through the viewport.
enum ReaderFlow {
  /// Reads content with vertical scrolling.
  scroll,

  /// Flows content into viewport-sized horizontal columns.
  paged,
}

/// A built-in color theme for the reading surface.
enum ReaderTheme {
  /// Dark text on a light background.
  light,

  /// Light text on a dark background.
  dark,

  /// Dark text on a warm background.
  sepia,
}

/// Display preferences applied to reflowable content documents.
final class ReaderSettings {
  /// Creates validated reading preferences.
  ///
  /// [fontScale] must be between 0.5 and 3.0, [lineHeight] between 1.0 and
  /// 2.5, and [margin] between 0 and 96 logical CSS pixels.
  ReaderSettings({
    this.flow = ReaderFlow.scroll,
    this.theme = ReaderTheme.light,
    this.fontScale = 1,
    this.lineHeight = 1.5,
    this.margin = 24,
  }) {
    if (!fontScale.isFinite ||
        fontScale < 0.5 ||
        fontScale > 3 ||
        !lineHeight.isFinite ||
        lineHeight < 1 ||
        lineHeight > 2.5 ||
        !margin.isFinite ||
        margin < 0 ||
        margin > 96) {
      throw ArgumentError('Reader settings are outside supported bounds.');
    }
  }

  /// The chapter flow mode.
  final ReaderFlow flow;

  /// The reading surface theme.
  final ReaderTheme theme;

  /// The root font-size multiplier.
  final double fontScale;

  /// The preferred line-height multiplier.
  final double lineHeight;

  /// The viewport margin in logical CSS pixels.
  final double margin;
}
