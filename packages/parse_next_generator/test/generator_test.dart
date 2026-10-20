import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:parse_next_generator/parse_next_generator.dart';
import 'package:test/test.dart';

final _builder = parseBuilder(BuilderOptions.empty);

final _runtime = {
  for (final f in Directory('../parse_next/lib').listSync(recursive: true))
    if (f is File && f.path.endsWith('.dart'))
      'parse_next|${f.path.substring('../parse_next/'.length)}': f
          .readAsStringSync(),
};

Future<TestBuilderResult> _build(Map<String, String> sources) => testBuilder(
  _builder,
  {..._runtime, ...sources},
  isInput: sources.containsKey,
  rootPackage: 'parse_next_it',
);

void main() {
  test('output matches the goldens byte for byte', () async {
    const sources = [
      'models/post',
      'models/user',
      'models/item',
      'models/note',
      'cloud',
    ];
    String read(String path) => File(path).readAsStringSync();
    final result = await testBuilder(
      _builder,
      {
        ..._runtime,
        for (final s in sources)
          'parse_next_it|lib/$s.dart': read('../parse_next_it/lib/$s.dart'),
      },
      isInput: (id) => id.startsWith('parse_next_it|'),
      rootPackage: 'parse_next_it',
      outputs: {
        for (final s in sources)
          'parse_next_it|lib/$s.parse.dart': read(
            'test/goldens/${s.split('/').last}.parse.dart.golden',
          ),
      },
    );
    expect(result.succeeded, isTrue);
  });

  group('fails the build', () {
    Future<void> rejects(String body, List<String> message) async {
      final result = await _build({
        'parse_next_it|lib/bad.dart':
            '''
import 'package:parse_next/parse_next.dart';

part 'bad.parse.dart';

final class Plain {
  const Plain();
}

@ParseClass('Target')
final class Target {
  const Target();
}

$body
''',
      });
      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf([for (final m in message) contains(m)]),
      );
    }

    test('on an unsupported field type', () {
      return rejects(
        '''
@ParseClass('Bad')
final class Bad {
  const Bad({required this.at});
  final Duration at;
}
''',
        ['Duration is not a supported field type', 'bad.dart:16:28'],
      );
    });

    for (final type in ['Pointer<Plain>', 'List<Pointer<Plain>>']) {
      test('on a $type whose target is not a @ParseClass', () {
        return rejects(
          '''
@ParseClass('Bad')
final class Bad {
  const Bad({required this.p});
  final $type p;
}
''',
          [
            '$type points to Plain, which is not a @ParseClass',
            'bad.dart:16:28',
          ],
        );
      });
    }

    test('on a Relation whose target is not a @ParseClass', () {
      return rejects(
        '''
@ParseClass('Bad')
final class Bad {
  const Bad({this.r = const Relation()});
  final Relation<Plain> r;
}
''',
        [
          'Relation<Plain> points to Plain, which is not a @ParseClass',
          'bad.dart:16:19',
        ],
      );
    });

    test('on two fields with one wire key', () {
      return rejects(
        '''
@ParseClass('Bad')
final class Bad {
  const Bad({required this.a, @ParseKey('a') required this.b});
  final String a;
  final String b;
}
''',
        ['b maps to the wire key "a", which a already uses', 'bad.dart:16:60'],
      );
    });

    test('on a positional parameter', () {
      return rejects(
        '''
@ParseClass('Bad')
final class Bad {
  const Bad(this.a);
  final String a;
}
''',
        ['a is positional', 'bad.dart:16:18'],
      );
    });

    test('without an unnamed constructor', () {
      return rejects(
        '''
@ParseClass('Bad')
final class Bad {
  const Bad.named({required this.a});
  final String a;
}
''',
        ['Bad has no unnamed constructor', 'bad.dart:15:13'],
      );
    });

    test('on a second GeoPoint field', () {
      return rejects(
        '''
@ParseClass('Bad')
final class Bad {
  const Bad({required this.a, this.b});
  final GeoPoint a;
  final GeoPoint? b;
}
''',
        ['b is a second GeoPoint field after a', 'bad.dart:16:36'],
      );
    });

    for (final (what, param, type, at) in [
      ('nullable', 'this.r', 'Relation<Target>?', 'bad.dart:16:19'),
      ('required', 'required this.r', 'Relation<Target>', 'bad.dart:16:28'),
    ]) {
      test('on a $what Relation', () {
        return rejects(
          '''
@ParseClass('Bad')
final class Bad {
  const Bad({$param});
  final $type r;
}
''',
          ['r must be a non-nullable Relation with a default', at],
        );
      });
    }
  });

  group('fails the build for @ParseFunctions', () {
    Future<void> rejects(String members, List<String> message) async {
      final result = await _build({
        'parse_next_it|lib/bad.dart':
            '''
import 'package:parse_next/parse_next.dart';

part 'bad.parse.dart';

final class Plain {
  const Plain();
}

@ParseFunctions()
abstract class Bad {
$members
}
''',
      });
      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf([for (final m in message) contains(m)]),
      );
    }

    const factory = '  factory Bad(ParseClient client) = _\$Bad;';

    test('on a method that does not return a Future', () {
      return rejects('$factory\n  int count();', [
        'count returns int; a cloud function method returns a Future',
        'bad.dart:12:7',
      ]);
    });

    test('on an unsupported parameter type', () {
      return rejects('$factory\n  Future<void> f({required Duration d});', [
        'Duration is not a supported parameter type',
        'bad.dart:12:37',
      ]);
    });

    test('on an unsupported return type', () {
      return rejects('$factory\n  Future<Duration> f();', [
        'Duration is not a supported return type',
        'bad.dart:12:20',
      ]);
    });

    test('on a Relation parameter', () {
      return rejects(
        '$factory\n  Future<void> f({required Relation<Plain> r});',
        ['Relation<Plain> is not a supported parameter type', 'bad.dart:12:44'],
      );
    });

    test('on a Doc parameter', () {
      return rejects('$factory\n  Future<void> f({required Doc<Plain> d});', [
        'Doc<Plain> is not a supported parameter type',
        'bad.dart:12:39',
      ]);
    });

    test('on a positional parameter', () {
      return rejects('$factory\n  Future<void> f(String s);', [
        's is positional',
        'bad.dart:12:25',
      ]);
    });

    test('on an optional positional parameter', () {
      return rejects('$factory\n  Future<void> f([String? s]);', [
        's is positional',
        'bad.dart:12:27',
      ]);
    });

    for (final (what, constructor) in [
      ('no constructor', ''),
      ('a generative constructor', '  Bad(ParseClient client);'),
      (
        'a factory with a body',
        '  factory Bad(ParseClient client) { throw 0; }',
      ),
      ('a redirect elsewhere', '  factory Bad(ParseClient client) = _\$Other;'),
      ('a parameter of another type', '  factory Bad(String client) = _\$Bad;'),
      (
        'a named parameter',
        '  factory Bad({required ParseClient client}) = _\$Bad;',
      ),
    ]) {
      test('on $what instead of the redirecting factory', () {
        return rejects('$constructor\n  Future<void> f();', [
          'Bad needs the constructor `factory Bad(ParseClient client) = '
              '_\$Bad;`',
          'bad.dart:10:16',
        ]);
      });
    }

    for (final (type, column) in [
      ('Pointer<Plain>', 43),
      ('List<Pointer<Plain>>', 49),
    ]) {
      test('on a $type parameter whose target is not a @ParseClass', () {
        return rejects('$factory\n  Future<void> f({required $type p});', [
          '$type points to Plain, which is not a @ParseClass',
          'bad.dart:12:$column',
        ]);
      });
    }

    for (final (type, column) in [
      ('Doc<Plain>', 22),
      ('List<Doc<Plain>>', 28),
      ('Doc<Plain>?', 23),
    ]) {
      test('on a $type return whose target is not a @ParseClass', () {
        return rejects('$factory\n  Future<$type> f();', [
          '$type points to Plain, which is not a @ParseClass',
          'bad.dart:12:$column',
        ]);
      });
    }

    test('on a method with a body', () {
      return rejects('$factory\n  Future<void> f() async {}', [
        'f has a body; a @ParseFunctions class has only abstract methods',
        'bad.dart:12:16',
      ]);
    });

    test('on a getter', () {
      return rejects('$factory\n  Future<int> get n;', [
        'n is a getter or setter',
        'bad.dart:12:19',
      ]);
    });

    test('on a setter', () {
      return rejects('$factory\n  set n(int v);', [
        'n is a getter or setter',
        'bad.dart:12:7',
      ]);
    });
  });
}
