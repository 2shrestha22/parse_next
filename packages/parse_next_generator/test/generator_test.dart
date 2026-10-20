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
  test('output matches the hand-written schemas byte for byte', () async {
    const models = ['post', 'user', 'item', 'note'];
    String read(String path) => File(path).readAsStringSync();
    final result = await testBuilder(
      _builder,
      {
        ..._runtime,
        for (final m in models)
          'parse_next_it|lib/models/$m.dart': read(
            '../parse_next_it/lib/models/$m.dart',
          ),
      },
      isInput: (id) => id.startsWith('parse_next_it|'),
      rootPackage: 'parse_next_it',
      outputs: {
        for (final m in models)
          'parse_next_it|lib/models/$m.parse.dart': read(
            'test/goldens/$m.parse.dart.golden',
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
}
