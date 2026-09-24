import 'package:readpub/readpub.dart';
import 'package:test/test.dart';

void main() {
  group('parsing and serialization', () {
    // Examples from EPUB CFI 1.1. Each canonical expression round-trips.
    for (final example in [
      'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/3:10)',
      'epubcfi(/6/14[chap05ref]!/4[body01]/10/2/1:3[2^[1^]])',
      'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/2/1:3[yyy])',
      'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/1:3[xx,y])',
      'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/2/1:3[,y])',
      'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/2/1:3[;s=b])',
      'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/2[;s=b])',
      'epubcfi(/6/4[chap01ref]!/4[body01]/16[svgimg])',
      'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/1:0)',
      'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05],/2/1:1,/3:4)',
      'epubcfi(/6/4!/4/10/2/1:3[Ф-"spa ce"-99%-aa^[bb^]^^])',
      'epubcfi(/4/2~23.5@50:30.25[;s=a])',
      'epubcfi(/4/2@0:100)',
      'epubcfi(/4/2!~0.5)',
    ]) {
      test('round-trips $example', () {
        final cfi = EpubCfi.parse(example);
        expect(cfi.toString(), example);
        expect(EpubCfi.parse(cfi.toString()), cfi);
      });
    }

    test('exposes steps, indirection, assertions and side bias', () {
      final cfi = EpubCfi.parse(
        'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/1:3[xx,y;s=a])',
      );
      final steps = cfi.path.steps;
      expect(steps.map((step) => step.index), [6, 4, 4, 10, 1]);
      expect(steps.map((step) => step.indirect), [false, false, true, false, false]);
      expect(steps[1].id, 'chap01ref');
      expect(steps[3].id, 'para05');
      expect(steps.last.isElement, isFalse);
      final offset = cfi.path.offset! as CfiCharacterOffset;
      expect(offset.offset, 3);
      expect(offset.textBefore, 'xx');
      expect(offset.textAfter, 'y');
      expect(offset.sideBias, CfiSideBias.after);
      expect(
        (EpubCfi.parse('epubcfi(/4/2[;s=b])').path.steps.last).sideBias,
        CfiSideBias.before,
      );
    });

    test('decodes circumflex escapes in assertions', () {
      final cfi = EpubCfi.parse(
        'epubcfi(/6/14[chap05ref]!/4[body01]/10/2/1:3[2^[1^]])',
      );
      expect((cfi.path.offset! as CfiCharacterOffset).textBefore, '2[1]');
      final special = EpubCfi.parse('epubcfi(/4[a^,b^;c^=d^(e^)]/1:0[^^])');
      expect(special.path.steps.first.id, 'a,b;c=d(e)');
      expect((special.path.offset! as CfiCharacterOffset).textBefore, '^');
      expect(special.toString(), 'epubcfi(/4[a^,b^;c^=d^(e^)]/1:0[^^])');
    });

    test('accepts expressions without the epubcfi wrapper', () {
      final partial = EpubCfi.parse('/4/2/1:3');
      expect(partial.expression, '/4/2/1:3');
      expect(partial.toString(), 'epubcfi(/4/2/1:3)');
      final range = EpubCfi.parse('/4/2/1,:3,:8');
      expect(range.isRange, isTrue);
      expect(range.start.expression, '/4/2/1:3');
      expect(range.end.expression, '/4/2/1:8');
    });

    test('splits ranges into complete start and end paths', () {
      final range = EpubCfi.parse(
        'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05],/2/1:1,/3:4)',
      );
      expect(range.isRange, isTrue);
      expect(range.path.toString(), '/6/4[chap01ref]!/4[body01]/10[para05]');
      expect(range.rangeStart.toString(), '/2/1:1');
      expect(range.rangeEnd.toString(), '/3:4');
      expect(
        range.start.toString(),
        'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/2/1:1)',
      );
      expect(
        range.end.toString(),
        'epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/3:4)',
      );
    });

    for (final invalid in [
      '',
      'epubcfi()',
      'epubcfi(/6/4',
      'epubcfi(/6/04)',
      'epubcfi(/6/4:01)',
      'epubcfi(/6/4/)',
      'epubcfi(!/4)',
      'epubcfi(/6/4!!/4)',
      'epubcfi(/6/4!)',
      'epubcfi(/6/4[])',
      'epubcfi(/6/4[a,b])',
      'epubcfi(/6/4[,b])',
      'epubcfi(/6/4[a)',
      'epubcfi(/6/4[a^b])',
      'epubcfi(/6/4[;s=a;s=b])',
      'epubcfi(/6/4[;s s=a])',
      'epubcfi(/6/4:3[;s=])',
      'epubcfi(/4/2~1.50)',
      'epubcfi(/4/2~1.)',
      'epubcfi(/4/2@101:0)',
      'epubcfi(/4/2@5)',
      'epubcfi(/4/2~3[text])',
      'epubcfi(/4/3/2)',
      'epubcfi(/4/2:3,:1,:2)',
      'epubcfi(/4/2,/1:5,/1:3)',
      'epubcfi(/4/2,/1:5)',
      'epubcfi(/4/2)x',
      'epubcfi(/4/1234567890123456)',
    ]) {
      test('rejects "$invalid"', () {
        expect(() => EpubCfi.parse(invalid), throwsFormatException);
        expect(EpubCfi.tryParse(invalid), isNull);
      });
    }

    test('reports the failing source offset', () {
      try {
        EpubCfi.parse('epubcfi(/6/4[a^b])');
        fail('expected a FormatException');
      } on FormatException catch (error) {
        expect(error.offset, 14);
        expect(error.source, 'epubcfi(/6/4[a^b])');
      }
    });

    test('bounds untrusted input length', () {
      final long = 'epubcfi(${'/2' * (EpubCfi.maxLength ~/ 2)})';
      expect(() => EpubCfi.parse(long), throwsFormatException);
    });
  });

  group('construction', () {
    test('serializes programmatic values canonically', () {
      final cfi = EpubCfi(
        CfiPath(
          [
            CfiStep(6),
            CfiStep(4, id: 'item]1'),
            CfiStep(2, indirect: true),
            CfiStep(1),
          ],
          offset: CfiCharacterOffset(
            5,
            textAfter: 'a,b',
            parameters: const {
              's': ['b'],
            },
          ),
        ),
      );
      expect(cfi.toString(), 'epubcfi(/6/4[item^]1]!/2/1:5[,a^,b;s=b])');
      expect(EpubCfi.parse(cfi.toString()), cfi);
      expect(CfiTemporalSpatialOffset(seconds: 0.0000001).toString(), '~0.0000001');
      expect(CfiTemporalSpatialOffset(seconds: 12).toString(), '~12');
    });

    test('validates values', () {
      expect(() => CfiStep(-2), throwsArgumentError);
      expect(() => CfiStep(2, id: ''), throwsArgumentError);
      expect(() => CfiCharacterOffset(-1), throwsArgumentError);
      expect(() => CfiCharacterOffset(1, textBefore: ''), throwsArgumentError);
      expect(() => CfiTemporalSpatialOffset(), throwsArgumentError);
      expect(() => CfiTemporalSpatialOffset(x: 1), throwsArgumentError);
      expect(() => CfiTemporalSpatialOffset(seconds: double.nan), throwsArgumentError);
      expect(() => EpubCfi(CfiPath([])), throwsArgumentError);
      expect(() => EpubCfi(CfiPath([CfiStep(4, indirect: true)])), throwsArgumentError);
      expect(
        () => CfiStep(2, parameters: const {'s': <String>[]}),
        throwsArgumentError,
      );
    });

    test('builds the smallest range between two points', () {
      EpubCfi point(String value) => EpubCfi.parse(value);
      final sameText = EpubCfi.between(
        point('epubcfi(/6/4!/4/10/1:3)'),
        point('epubcfi(/6/4!/4/10/1:8)'),
      );
      expect(sameText.toString(), 'epubcfi(/6/4!/4/10/1,:3,:8)');
      final nested = EpubCfi.between(
        point('epubcfi(/6/4!/4/10)'),
        point('epubcfi(/6/4!/4/10/3:4)'),
      );
      expect(nested.toString(), 'epubcfi(/6/4!/4,/10,/10/3:4)');
      final documents = EpubCfi.between(
        point('epubcfi(/6/4!/4/2/1:0)'),
        point('epubcfi(/6/6!/4/2/1:5)'),
      );
      expect(documents.toString(), 'epubcfi(/6,/4!/4/2/1:0,/6!/4/2/1:5)');
      expect(documents.start, point('epubcfi(/6/4!/4/2/1:0)'));
      expect(
        () => EpubCfi.between(point('epubcfi(/6/6)'), point('epubcfi(/6/4)')),
        throwsArgumentError,
      );
      expect(
        () => EpubCfi.between(point('epubcfi(/4)'), point('epubcfi(/6)')),
        throwsArgumentError,
      );
    });
  });

  group('sorting', () {
    test('orders steps, offsets and indirections by specification rules', () {
      final ordered = [
        'epubcfi(/4)',
        'epubcfi(/4:3)',
        'epubcfi(/4/1:0)',
        'epubcfi(/4/1:5)',
        'epubcfi(/4/2)',
        'epubcfi(/4/2@0:0)',
        'epubcfi(/4/2@90:0)',
        'epubcfi(/4/2@0:10)',
        'epubcfi(/4/2~1)',
        'epubcfi(/4/2~1@0:0)',
        'epubcfi(/4/2~2)',
        'epubcfi(/4/2!/2)',
        'epubcfi(/4/3)',
        'epubcfi(/4/10)',
        'epubcfi(/6)',
      ].map(EpubCfi.parse).toList();
      final shuffled = [...ordered.reversed]..sort();
      expect(shuffled, ordered);
    });

    test('ignores assertions and compares ranges by start then end', () {
      final plain = EpubCfi.parse('epubcfi(/6/4!/4/2/1:3)');
      final asserted = EpubCfi.parse('epubcfi(/6/4[x]!/4[y]/2/1:3[abc;s=b])');
      expect(plain.compareTo(asserted), 0);
      expect(plain, isNot(asserted));
      final short = EpubCfi.parse('epubcfi(/6/4!/4/2/1,:3,:5)');
      final long = EpubCfi.parse('epubcfi(/6/4!/4/2/1,:3,:9)');
      expect(short.compareTo(long), lessThan(0));
      expect(plain.compareTo(short), lessThan(0));
      expect(long.contains(short.end), isTrue);
      expect(short.contains(long.end), isFalse);
      expect(long.contains(EpubCfi.parse('epubcfi(/6/4!/4/2/1:4)')), isTrue);
    });
  });
}
