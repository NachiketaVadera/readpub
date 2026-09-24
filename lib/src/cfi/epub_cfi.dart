import 'package:collection/collection.dart';

part 'cfi_parser.dart';

const _parameterEquality = MapEquality<String, List<String>>(
  values: ListEquality<String>(),
);

/// The side of an ambiguous location to which a CFI point is attached.
enum CfiSideBias {
  /// The point attaches to the content preceding it in document order.
  before,

  /// The point attaches to the content following it in document order.
  after,
}

/// An EPUB Canonical Fragment Identifier (EPUB CFI 1.1).
///
/// A CFI is either a point, identified by [path], or a range, identified by a
/// common parent [path] and the local paths [rangeStart] and [rangeEnd].
/// Instances are immutable syntax trees; they do not know which publication or
/// document they refer to. A CFI whose first step references the package
/// document spine is a publication CFI. An expression whose steps start at the
/// root element of a content document is a content-document CFI, like the
/// Readium `partialCfi` extension.
///
/// [compareTo] implements the specification sorting rules, which ignore all
/// bracketed assertions. Equality is structural and includes assertions.
final class EpubCfi implements Comparable<EpubCfi> {
  /// Creates a point CFI.
  ///
  /// [path] must start with a step that is not an indirection.
  EpubCfi(this.path) : rangeStart = null, rangeEnd = null {
    _checkMainPath(path);
  }

  /// Creates a range CFI from a common [path] and two local paths.
  ///
  /// [path] must end at a step, and the start must not follow the end.
  EpubCfi.range(this.path, CfiPath start, CfiPath end)
    : rangeStart = start,
      rangeEnd = end {
    _checkMainPath(path);
    if (path.offset != null) {
      throw ArgumentError.value(path, 'path', 'A range parent must end at a step.');
    }
    if (_comparePaths(startPath, endPath) > 0) {
      throw ArgumentError('A CFI range start must not follow its end.');
    }
  }

  /// Creates the smallest range CFI spanning two point CFIs.
  ///
  /// The common parent contains at least one step. Throws an [ArgumentError]
  /// when either argument is a range or [start] follows [end].
  factory EpubCfi.between(EpubCfi start, EpubCfi end) {
    if (start.isRange || end.isRange) {
      throw ArgumentError('A CFI range must be created from two points.');
    }
    final a = start.path.steps;
    final b = end.path.steps;
    var common = 0;
    while (common < a.length && common < b.length && a[common] == b[common]) {
      common++;
    }
    bool emptyLocal(List<CfiStep> steps, CfiOffset? offset) =>
        steps.length == common && offset == null;
    while (common > 1 &&
        (emptyLocal(a, start.path.offset) || emptyLocal(b, end.path.offset))) {
      common--;
    }
    if (common == 0) {
      throw ArgumentError('CFI points have no common parent step.');
    }
    return EpubCfi.range(
      CfiPath(a.take(common)),
      CfiPath(a.skip(common), offset: start.path.offset),
      CfiPath(b.skip(common), offset: end.path.offset),
    );
  }

  /// Parses a CFI expression with or without its `epubcfi(...)` wrapper.
  ///
  /// The expression must follow the EPUB CFI 1.1 grammar. URI percent-encoding
  /// must be decoded by the caller first. Throws a [FormatException] with the
  /// failing source offset for invalid input.
  factory EpubCfi.parse(String source) => _CfiParser(source).parse();

  /// Parses [source] like [EpubCfi.parse], returning null when it is invalid.
  static EpubCfi? tryParse(String source) {
    try {
      return EpubCfi.parse(source);
    } on FormatException {
      return null;
    }
  }

  /// The maximum source length accepted by [EpubCfi.parse].
  static const maxLength = 65536;

  /// The point path, or the common parent path of a range.
  final CfiPath path;

  /// The range start relative to [path], or null for a point.
  final CfiPath? rangeStart;

  /// The range end relative to [path], or null for a point.
  final CfiPath? rangeEnd;

  /// Whether this CFI identifies a range.
  bool get isRange => rangeStart != null;

  /// The complete path of the point, or of the range start.
  CfiPath get startPath => isRange ? path.join(rangeStart!) : path;

  /// The complete path of the point, or of the range end.
  CfiPath get endPath => isRange ? path.join(rangeEnd!) : path;

  /// The point CFI at the start of this CFI.
  EpubCfi get start => isRange ? EpubCfi(startPath) : this;

  /// The point CFI at the end of this CFI.
  EpubCfi get end => isRange ? EpubCfi(endPath) : this;

  /// Whether [other] lies within this CFI according to CFI sorting rules.
  ///
  /// A point contains only equivalent points. Assertions are ignored.
  bool contains(EpubCfi other) =>
      _comparePaths(startPath, other.startPath) <= 0 &&
      _comparePaths(other.endPath, endPath) <= 0;

  /// The expression without the `epubcfi(...)` wrapper.
  String get expression => isRange ? '$path,$rangeStart,$rangeEnd' : path.toString();

  /// Compares CFIs by their start and then their end.
  ///
  /// Assertions and side bias are ignored, as the specification requires.
  @override
  int compareTo(EpubCfi other) {
    final start = _comparePaths(startPath, other.startPath);
    return start != 0 ? start : _comparePaths(endPath, other.endPath);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubCfi &&
      other.path == path &&
      other.rangeStart == rangeStart &&
      other.rangeEnd == rangeEnd;

  @override
  int get hashCode => Object.hash(path, rangeStart, rangeEnd);

  /// The canonical CFI with its `epubcfi(...)` wrapper.
  @override
  String toString() => 'epubcfi($expression)';
}

/// A sequence of CFI steps with an optional terminal offset.
///
/// Indirections are represented by [CfiStep.indirect] and
/// [CfiOffset.indirect]. A complete path must start with a direct step; local
/// paths inside a range may be empty or start with an indirection.
final class CfiPath {
  /// Creates a CFI path.
  CfiPath(Iterable<CfiStep> steps, {this.offset}) : steps = List.unmodifiable(steps) {
    for (var i = 0; i + 1 < this.steps.length; i++) {
      if (this.steps[i].index.isOdd && !this.steps[i + 1].indirect) {
        throw ArgumentError('A character data step cannot have child steps.');
      }
    }
  }

  /// The steps, in document order.
  final List<CfiStep> steps;

  /// The terminal offset, if any.
  final CfiOffset? offset;

  /// Whether this path has neither steps nor an offset.
  bool get isEmpty => steps.isEmpty && offset == null;

  /// Appends [local] to this path, which must not end with an offset.
  CfiPath join(CfiPath local) {
    if (offset != null) {
      throw ArgumentError('A CFI path ending with an offset cannot be extended.');
    }
    return CfiPath([...steps, ...local.steps], offset: local.offset);
  }

  @override
  bool operator ==(Object other) =>
      other is CfiPath &&
      const ListEquality<CfiStep>().equals(other.steps, steps) &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(Object.hashAll(steps), offset);

  /// The canonical path expression.
  @override
  String toString() => '${steps.join()}${offset ?? ''}';
}

/// A CFI step to a child element, a character data chunk or a virtual child.
///
/// Even indices refer to child elements: 2 is the first element child. Odd
/// indices refer to the possibly-empty character data chunks around them. The
/// index 0 and the index after the last element are virtual positions.
final class CfiStep {
  /// Creates a validated step.
  CfiStep(
    this.index, {
    this.id,
    Map<String, List<String>> parameters = const {},
    this.indirect = false,
  }) : parameters = _frozenParameters(parameters) {
    if (index < 0) throw ArgumentError.value(index, 'index', 'Must not be negative.');
    if (id != null && id!.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
  }

  /// The child index.
  final int index;

  /// The ID assertion for the target element.
  final String? id;

  /// Assertion parameters, such as the side-bias parameter `s`.
  final Map<String, List<String>> parameters;

  /// Whether this step follows an indirection (`!`) into a referenced document.
  final bool indirect;

  /// Whether this step refers to an element or virtual element position.
  bool get isElement => index.isEven;

  /// The declared side bias, when valid.
  CfiSideBias? get sideBias => _sideBias(parameters);

  /// Returns a copy with [indirect] replaced.
  CfiStep withIndirect(bool indirect) =>
      CfiStep(index, id: id, parameters: parameters, indirect: indirect);

  @override
  bool operator ==(Object other) =>
      other is CfiStep &&
      other.index == index &&
      other.id == id &&
      other.indirect == indirect &&
      _parameterEquality.equals(other.parameters, parameters);

  @override
  int get hashCode =>
      Object.hash(index, id, indirect, _parameterEquality.hash(parameters));

  @override
  String toString() =>
      '${indirect ? '!' : ''}/$index${_assertion(id, null, parameters)}';
}

/// A terminal CFI offset.
sealed class CfiOffset {
  CfiOffset._(Map<String, List<String>> parameters, this.indirect)
    : parameters = _frozenParameters(parameters);

  /// Assertion parameters, such as the side-bias parameter `s`.
  final Map<String, List<String>> parameters;

  /// Whether this offset follows an indirection (`!`).
  final bool indirect;

  /// The declared side bias, when valid.
  CfiSideBias? get sideBias => _sideBias(parameters);
}

/// A character offset in UTF-16 code units, with an optional text assertion.
final class CfiCharacterOffset extends CfiOffset {
  /// Creates a validated character offset.
  ///
  /// [textBefore] and [textAfter] assert the text around the point.
  CfiCharacterOffset(
    this.offset, {
    this.textBefore,
    this.textAfter,
    Map<String, List<String>> parameters = const {},
    bool indirect = false,
  }) : super._(parameters, indirect) {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (textBefore?.isEmpty == true || textAfter?.isEmpty == true) {
      throw ArgumentError('Text assertions must not be empty.');
    }
  }

  /// The zero-based UTF-16 code-unit offset.
  final int offset;

  /// Text expected immediately before the point.
  final String? textBefore;

  /// Text expected immediately after the point.
  final String? textAfter;

  @override
  bool operator ==(Object other) =>
      other is CfiCharacterOffset &&
      other.offset == offset &&
      other.textBefore == textBefore &&
      other.textAfter == textAfter &&
      other.indirect == indirect &&
      _parameterEquality.equals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(
    offset,
    textBefore,
    textAfter,
    indirect,
    _parameterEquality.hash(parameters),
  );

  @override
  String toString() =>
      '${indirect ? '!' : ''}:$offset${_assertion(textBefore, textAfter, parameters)}';
}

/// A temporal offset in seconds and/or a spatial offset in percent.
final class CfiTemporalSpatialOffset extends CfiOffset {
  /// Creates a validated temporal and/or spatial offset.
  ///
  /// [seconds] must be finite and not negative. [x] and [y] must be supplied
  /// together and lie from 0 to 100.
  CfiTemporalSpatialOffset({
    this.seconds,
    this.x,
    this.y,
    Map<String, List<String>> parameters = const {},
    bool indirect = false,
  }) : super._(parameters, indirect) {
    if (seconds == null && x == null && y == null) {
      throw ArgumentError('A temporal-spatial offset needs a value.');
    }
    if ((x == null) != (y == null)) {
      throw ArgumentError('Spatial offsets need both x and y.');
    }
    if (seconds != null && (!seconds!.isFinite || seconds! < 0 || seconds! >= 1e15)) {
      throw ArgumentError.value(
        seconds,
        'seconds',
        'Must be a finite, non-negative time.',
      );
    }
    for (final value in [x, y]) {
      if (value != null && (!value.isFinite || value < 0 || value > 100)) {
        throw ArgumentError.value(value, 'spatial offset', 'Must be from 0 to 100.');
      }
    }
  }

  /// The temporal position in seconds.
  final double? seconds;

  /// The horizontal position, as a percentage of the width.
  final double? x;

  /// The vertical position, as a percentage of the height.
  final double? y;

  @override
  bool operator ==(Object other) =>
      other is CfiTemporalSpatialOffset &&
      other.seconds == seconds &&
      other.x == x &&
      other.y == y &&
      other.indirect == indirect &&
      _parameterEquality.equals(other.parameters, parameters);

  @override
  int get hashCode =>
      Object.hash(seconds, x, y, indirect, _parameterEquality.hash(parameters));

  @override
  String toString() {
    final buffer = StringBuffer(indirect ? '!' : '');
    if (seconds != null) buffer.write('~${_formatNumber(seconds!)}');
    if (x != null) buffer.write('@${_formatNumber(x!)}:${_formatNumber(y!)}');
    buffer.write(_assertion(null, null, parameters));
    return buffer.toString();
  }
}

void _checkMainPath(CfiPath path) {
  if (path.steps.isEmpty || path.steps.first.indirect) {
    throw ArgumentError.value(path, 'path', 'Must start with a direct step.');
  }
}

Map<String, List<String>> _frozenParameters(Map<String, List<String>> parameters) {
  for (final entry in parameters.entries) {
    if (entry.key.isEmpty ||
        entry.key.contains(' ') ||
        entry.value.isEmpty ||
        entry.value.any((value) => value.isEmpty)) {
      throw ArgumentError.value(
        parameters,
        'parameters',
        'Names must be non-empty without spaces; values must be non-empty.',
      );
    }
  }
  return Map.unmodifiable({
    for (final entry in parameters.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  });
}

CfiSideBias? _sideBias(Map<String, List<String>> parameters) =>
    switch (parameters['s']) {
      ['a'] => CfiSideBias.after,
      ['b'] => CfiSideBias.before,
      _ => null,
    };

const _specialCharacters = '^[](),;=';

String _escape(String value) {
  final buffer = StringBuffer();
  for (final unit in value.split('')) {
    if (_specialCharacters.contains(unit)) buffer.write('^');
    buffer.write(unit);
  }
  return buffer.toString();
}

String _assertion(String? first, String? second, Map<String, List<String>> parameters) {
  if (first == null && second == null && parameters.isEmpty) return '';
  final buffer = StringBuffer('[');
  if (first != null) buffer.write(_escape(first));
  if (second != null) buffer.write(',${_escape(second)}');
  for (final entry in parameters.entries) {
    buffer.write(';${_escape(entry.key)}=${entry.value.map(_escape).join(',')}');
  }
  buffer.write(']');
  return buffer.toString();
}

String _formatNumber(double value) {
  if (value == value.truncateToDouble()) return value.toInt().toString();
  var text = value.toString();
  if (text.contains('e')) text = value.toStringAsFixed(20);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text;
}

// Sorting ranks from the specification, least important first. The end of a
// path sorts before every other token, so an ancestor precedes descendants.
const _endRank = 0;
const _characterRank = 1;
const _childRank = 2;
const _temporalSpatialRank = 3;
const _indirectionRank = 4;

List<(int, Object?)> _tokens(CfiPath path) => [
  for (final step in path.steps) ...[
    if (step.indirect) (_indirectionRank, null),
    (_childRank, step.index),
  ],
  if (path.offset case final offset?) ...[
    if (offset.indirect) (_indirectionRank, null),
    switch (offset) {
      CfiCharacterOffset() => (_characterRank, offset.offset),
      CfiTemporalSpatialOffset() => (_temporalSpatialRank, offset),
    },
  ],
];

int _compareOptional(double? a, double? b) {
  if (a == null || b == null) return a == null ? (b == null ? 0 : -1) : 1;
  return a.compareTo(b);
}

int _comparePaths(CfiPath first, CfiPath second) {
  final a = _tokens(first);
  final b = _tokens(second);
  for (var i = 0; ; i++) {
    final (rankA, valueA) = i < a.length ? a[i] : (_endRank, null);
    final (rankB, valueB) = i < b.length ? b[i] : (_endRank, null);
    if (rankA != rankB) return rankA.compareTo(rankB);
    final result = switch (rankA) {
      _endRank => 0,
      _childRank || _characterRank => (valueA as int).compareTo(valueB as int),
      _temporalSpatialRank => _compareMedia(
        valueA as CfiTemporalSpatialOffset,
        valueB as CfiTemporalSpatialOffset,
      ),
      _ => 0,
    };
    if (result != 0 || rankA == _endRank) return result;
  }
}

int _compareMedia(CfiTemporalSpatialOffset a, CfiTemporalSpatialOffset b) {
  final time = _compareOptional(a.seconds, b.seconds);
  if (time != 0) return time;
  final y = _compareOptional(a.y, b.y);
  return y != 0 ? y : _compareOptional(a.x, b.x);
}
