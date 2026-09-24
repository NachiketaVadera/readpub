import 'dart:ui' show Color, Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:readpub/readpub.dart';

/// How a [ReaderDecoration] is drawn.
enum ReaderDecorationKind {
  /// A translucent background behind the text.
  highlight,

  /// A line under the text.
  underline,
}

/// The appearance of a [ReaderDecoration].
@immutable
final class ReaderDecorationStyle {
  /// A highlight in [color]; its alpha sets the opacity.
  const ReaderDecorationStyle.highlight([this.color = const Color(0x70ffd54f)])
    : kind = ReaderDecorationKind.highlight;

  /// An underline in [color]; its alpha sets the opacity.
  const ReaderDecorationStyle.underline([this.color = const Color(0xffe53935)])
    : kind = ReaderDecorationKind.underline;

  /// How the decoration is drawn.
  final ReaderDecorationKind kind;

  /// The decoration color.
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is ReaderDecorationStyle &&
      other.kind == kind &&
      other.color == color;

  @override
  int get hashCode => Object.hash(kind, color);
}

/// A range of publication text drawn with a [style], such as a highlight.
///
/// The [locator] identifies the text by the start CFI and `text.highlight`
/// that `ReaderController.selectionLocator` and
/// `ReadingServices.locatorForTextRange` produce, or by a range CFI. It is
/// restored through `ReadingServices.resolve`, so a decoration saved for an
/// earlier edition of a book is drawn where its text is found; a decoration
/// whose text cannot be found is not drawn.
@immutable
final class ReaderDecoration {
  /// Creates a decoration identified by [id] within its group.
  const ReaderDecoration({
    required this.id,
    required this.locator,
    this.style = const ReaderDecorationStyle.highlight(),
  });

  /// Identifies the decoration within its group.
  final String id;

  /// The decorated text.
  final Locator locator;

  /// How the decoration is drawn.
  final ReaderDecorationStyle style;

  @override
  bool operator ==(Object other) =>
      other is ReaderDecoration &&
      other.id == id &&
      other.locator == locator &&
      other.style == style;

  @override
  int get hashCode => Object.hash(id, locator, style);
}

/// A tap on a drawn [ReaderDecoration].
@immutable
final class ReaderDecorationActivation {
  /// Creates an activation.
  const ReaderDecorationActivation({
    required this.group,
    required this.decoration,
    required this.point,
    this.rect,
  });

  /// The group containing [decoration].
  final String group;

  /// The tapped decoration.
  final ReaderDecoration decoration;

  /// The tap position.
  final Offset point;

  /// The bounds of the decoration's visible part, for anchoring a menu.
  ///
  /// Positions are relative to the top-left of the reader surface, in CSS
  /// pixels, which equal logical pixels at the reader's default scale.
  final Rect? rect;
}
