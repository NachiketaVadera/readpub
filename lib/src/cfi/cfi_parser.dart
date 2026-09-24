part of 'epub_cfi.dart';

/// A recursive-descent parser for the EPUB CFI 1.1 grammar.
final class _CfiParser {
  _CfiParser(this.source);

  final String source;
  int _position = 0;

  EpubCfi parse() {
    if (source.length > EpubCfi.maxLength) {
      throw FormatException('EPUB CFI exceeds ${EpubCfi.maxLength} characters.');
    }
    final wrapped = source.startsWith('epubcfi(');
    if (wrapped) _position = 8;
    final pathStart = _position;
    final path = _path();
    if (path.steps.isEmpty || path.steps.first.indirect) {
      _fail('A CFI path must start with a step.', pathStart);
    }
    EpubCfi result;
    if (_peek == ',') {
      if (path.offset != null) {
        _fail('A CFI range parent must end at a step.');
      }
      _position++;
      final start = _path();
      _expect(',');
      final end = _path();
      result = _build(() => EpubCfi.range(path, start, end), pathStart);
    } else {
      result = _build(() => EpubCfi(path), pathStart);
    }
    if (wrapped) _expect(')');
    if (_position != source.length) _fail('Unexpected character in EPUB CFI.');
    return result;
  }

  String? get _peek => _position < source.length ? source[_position] : null;

  Never _fail(String message, [int? offset]) =>
      throw FormatException(message, source, offset ?? _position);

  void _expect(String character) {
    if (_peek != character) _fail('Expected "$character" in EPUB CFI.');
    _position++;
  }

  T _build<T>(T Function() build, int offset) {
    try {
      return build();
    } on ArgumentError catch (error) {
      _fail('Invalid EPUB CFI: ${error.message}', offset);
    }
  }

  // local_path = { step } , ( redirected_path | [ offset ] )
  // redirected_path = "!" , ( offset | path )
  CfiPath _path() {
    final start = _position;
    final steps = <CfiStep>[];
    var indirect = false;
    CfiOffset? offset;
    while (true) {
      switch (_peek) {
        case '/':
          steps.add(_step(indirect));
          indirect = false;
        case '!':
          if (indirect) _fail('Repeated EPUB CFI indirection.');
          _position++;
          indirect = true;
        case ':' || '@' || '~':
          offset = _offset(indirect);
          indirect = false;
        default:
          if (indirect) _fail('An EPUB CFI indirection needs a step or offset.');
          return _build(() => CfiPath(steps, offset: offset), start);
      }
      if (offset != null) {
        return _build(() => CfiPath(steps, offset: offset), start);
      }
    }
  }

  // step = "/" , integer , [ "[" , assertion , "]" ]
  CfiStep _step(bool indirect) {
    final start = _position;
    _expect('/');
    final index = _integer();
    if (_peek != '[') return CfiStep(index, indirect: indirect);
    final (id, second, parameters) = _assertion();
    if (second != null) {
      _fail('A step assertion accepts only an element ID.', start);
    }
    return _build(
      () => CfiStep(index, id: id, parameters: parameters, indirect: indirect),
      start,
    );
  }

  // offset = ( ":" integer | "@" number ":" number |
  //            "~" number [ "@" number ":" number ] ) [ "[" assertion "]" ]
  CfiOffset _offset(bool indirect) {
    final start = _position;
    if (_peek == ':') {
      _position++;
      final value = _integer();
      final (before, after, parameters) = _peek == '['
          ? _assertion()
          : (null, null, const <String, List<String>>{});
      return _build(
        () => CfiCharacterOffset(
          value,
          textBefore: before,
          textAfter: after,
          parameters: parameters,
          indirect: indirect,
        ),
        start,
      );
    }
    double? seconds;
    double? x;
    double? y;
    if (_peek == '~') {
      _position++;
      seconds = _number();
    }
    if (_peek == '@') {
      _position++;
      x = _number();
      _expect(':');
      y = _number();
    }
    var parameters = const <String, List<String>>{};
    if (_peek == '[') {
      final (first, second, values) = _assertion();
      if (first != null || second != null) {
        _fail('Text assertions must follow a character offset.', start);
      }
      parameters = values;
    }
    return _build(
      () => CfiTemporalSpatialOffset(
        seconds: seconds,
        x: x,
        y: y,
        parameters: parameters,
        indirect: indirect,
      ),
      start,
    );
  }

  // integer = zero | ( digit-non-zero , { digit } )
  int _integer() {
    final start = _position;
    while (_isDigit(_peek)) {
      _position++;
    }
    final digits = source.substring(start, _position);
    if (digits.isEmpty) _fail('Expected an integer in EPUB CFI.');
    if (digits.length > 1 && digits.startsWith('0')) {
      _fail('EPUB CFI integers must not have leading zeros.', start);
    }
    if (digits.length > 15) _fail('EPUB CFI integer is too large.', start);
    return int.parse(digits);
  }

  // number = ( digit-non-zero { digit } | zero ) [ "." { digit } digit-non-zero ]
  double _number() {
    final start = _position;
    _integer();
    if (_peek == '.') {
      _position++;
      final fraction = _position;
      while (_isDigit(_peek)) {
        _position++;
      }
      if (_position == fraction || source[_position - 1] == '0') {
        _fail('EPUB CFI decimal fractions must end with a non-zero digit.', start);
      }
      if (_position - fraction > 20) _fail('EPUB CFI number is too precise.', start);
    }
    return double.parse(source.substring(start, _position));
  }

  // assertion = ( ( value [ "," value ] ) | ( "," value ) | parameter )
  //             { parameter }
  (String?, String?, Map<String, List<String>>) _assertion() {
    _expect('[');
    String? first;
    String? second;
    if (_peek == ',') {
      _position++;
      second = _value();
    } else if (_peek != ';') {
      first = _value();
      if (_peek == ',') {
        _position++;
        second = _value();
      }
    }
    final parameters = <String, List<String>>{};
    while (_peek == ';') {
      _position++;
      final nameStart = _position;
      final name = _value();
      if (name.contains(' ')) _fail('EPUB CFI parameter names cannot contain spaces.');
      if (parameters.containsKey(name)) {
        _fail('Duplicate EPUB CFI parameter "$name".', nameStart);
      }
      _expect('=');
      final values = [_value()];
      while (_peek == ',') {
        _position++;
        values.add(_value());
      }
      parameters[name] = values;
    }
    if (first == null && second == null && parameters.isEmpty) {
      _fail('An EPUB CFI assertion must not be empty.');
    }
    _expect(']');
    return (first, second, parameters);
  }

  // value = character-escaped-special , { character-escaped-special }
  String _value() {
    final buffer = StringBuffer();
    while (true) {
      final character = _peek;
      if (character == null) _fail('Unterminated EPUB CFI assertion.');
      if (character == '^') {
        final escaped = _position + 1 < source.length ? source[_position + 1] : null;
        if (escaped == null || !_specialCharacters.contains(escaped)) {
          _fail('Invalid EPUB CFI circumflex escape.');
        }
        buffer.write(escaped);
        _position += 2;
      } else if (_specialCharacters.contains(character)) {
        break;
      } else {
        buffer.write(character);
        _position++;
      }
    }
    if (buffer.isEmpty) _fail('Expected an EPUB CFI assertion value.');
    return buffer.toString();
  }

  static bool _isDigit(String? value) =>
      value != null && value.codeUnitAt(0) >= 0x30 && value.codeUnitAt(0) <= 0x39;
}
