import 'dart:convert';
import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';
import 'package:test/test.dart';

import 'models.dart';

Json parse(String source) => Json(jsonDecode(source) as Map<String, Object?>);

enum Mood { happy, sad }

Matcher decodeError(String key) =>
    throwsA(isA<DecodeError>().having((e) => e.key, 'key', key));

void main() {
  group('Json', () {
    test('Unicode strings survive decoding', () {
      const s = 'Hello, wörld 👋 — 日本語 \u{1F600}';
      expect(parse(jsonEncode({'s': s})).require<String>('s'), s);
    });

    test('empty arrays decode as empty lists', () {
      final j = parse('{"tags": [], "authors": []}');
      expect(j.optList<String>('tags'), isEmpty);
      expect(j.optPointerList('authors', authorSchema), isEmpty);
    });

    test('null and absent both read as absent', () {
      for (final j in [parse('{"x": null}'), parse('{}')]) {
        expect(j.opt<String>('x'), isNull);
        expect(j.optList<String>('x'), isNull);
        expect(j.optPointer('x', authorSchema), isNull);
        expect(() => j.require<String>('x'), decodeError('x'));
      }
    });

    test('required lists and pointers reject null and absent', () {
      for (final j in [parse('{"x": null}'), parse('{}')]) {
        expect(() => j.requireList<String>('x'), decodeError('x'));
        expect(() => j.requirePointer('x', authorSchema), decodeError('x'));
        expect(() => j.requirePointerList('x', authorSchema), decodeError('x'));
        expect(() => j.requireEnum('x', Mood.values), decodeError('x'));
        expect(j.optEnum('x', Mood.values), isNull);
      }
      final j = parse('{"l": ["a"], "p": {"__type": "Pointer",'
          ' "className": "Author", "objectId": "a1"}}');
      expect(j.requireList<String>('l'), ['a']);
      expect(j.requirePointer('p', authorSchema).id, 'a1');
    });

    test('enums decode by name; an unknown name is a DecodeError', () {
      final j = parse('{"m": "sad", "u": "Sad"}');
      expect(j.requireEnum('m', Mood.values), Mood.sad);
      expect(j.optEnum('m', Mood.values), Mood.sad);
      expect(() => j.requireEnum('u', Mood.values), decodeError('u'));
      expect(() => j.optEnum('u', Mood.values), decodeError('u'));
    });

    test('a value of the wrong type names its key', () {
      expect(() => parse('{"x": 1}').require<String>('x'), decodeError('x'));
      expect(() => parse('{"x": [1, "a"]}').optList<int>('x'),
          decodeError('x[1]'));
      expect(() => parse('{"x": [null]}').optList<String>('x'),
          decodeError('x[0]'));
    });

    test('an unknown __type raises DecodeError', () {
      final j = parse('{"x": {"__type": "Weird"}}');
      expect(() => j.require<GeoPoint>('x'), decodeError('x'));
      expect(() => j.require<Json>('x'), decodeError('x'));
      expect(() => j.require<Object>('x'), decodeError('x'));
      expect(() => j.optPointer('x', authorSchema), decodeError('x'));
      expect(() => j.relation('x', authorSchema), decodeError('x'));
    });
  });

  group('numbers', () {
    // jsonDecode gives 2.0 a double on the VM and an int-typed JS number on
    // the web; both must decode the same way.
    final j = parse('{"whole": 2.0, "int": 2, "frac": 1.5}');

    test('int fields accept whole numbers in either form', () {
      expect(j.require<int>('whole'), 2);
      expect(j.require<int>('whole'), isA<int>());
      expect(j.require<int>('int'), 2);
    });

    test('int fields reject fractions', () {
      expect(() => j.require<int>('frac'), decodeError('frac'));
    });

    test('double fields accept ints', () {
      expect(j.require<double>('int'), 2.0);
      expect(j.require<double>('int'), isA<double>());
      expect(j.require<double>('frac'), 1.5);
    });

    test('num fields accept both', () {
      expect(j.require<num>('int'), 2);
      expect(j.require<num>('frac'), 1.5);
    });

    test('list elements are converted too', () {
      expect(parse('{"x": [1.0, 2]}').optList<int>('x'), [1, 2]);
      expect(parse('{"x": [1, 2.5]}').optList<double>('x'), [1.0, 2.5]);
    });
  });

  group('Date', () {
    test('decodes the Date object and the plain ISO string', () {
      final j =
          parse('{"d": {"__type": "Date", "iso": "2024-01-02T03:04:05.678Z"},'
              ' "createdAt": "2024-01-02T03:04:05.678Z"}');
      final expected = DateTime.utc(2024, 1, 2, 3, 4, 5, 678);
      expect(j.require<DateTime>('d'), expected);
      expect(j.require<DateTime>('createdAt'), expected);
      expect(j.require<DateTime>('d').isUtc, isTrue);
    });

    test('an offset is converted to UTC; no zone is rejected', () {
      final j = parse('{"a": "2024-01-02T08:49:05.678+05:45",'
          ' "b": "2024-01-02T03:04:05.678"}');
      expect(j.require<DateTime>('a'), DateTime.utc(2024, 1, 2, 3, 4, 5, 678));
      expect(() => j.require<DateTime>('b'), decodeError('b'));
    });

    test('encodes UTC at millisecond precision', () {
      expect(encodeDate(DateTime.utc(2024, 1, 2, 3, 4, 5, 678, 999)),
          {'__type': 'Date', 'iso': '2024-01-02T03:04:05.678Z'});
    });

    test('non-UTC input is converted to UTC on encode', () {
      final local = DateTime(2024, 1, 2, 3, 4, 5, 678);
      final iso = encodeDate(local)['iso']! as String;
      expect(iso, endsWith('Z'));
      expect(DateTime.parse(iso).isAtSameMomentAs(local), isTrue);
      expect(iso, local.toUtc().toIso8601String());
    });

    test('a malformed iso names the nested key', () {
      expect(
          () => parse('{"d": {"__type": "Date", "iso": "nope"}}')
              .require<DateTime>('d'),
          decodeError('d.iso'));
    });
  });

  group('GeoPoint', () {
    test('accepts the exact edges', () {
      for (final (lat, lng) in [(90.0, 180.0), (-90.0, -180.0), (0.0, 0.0)]) {
        final p = GeoPoint(lat, lng);
        expect((p.latitude, p.longitude), (lat, lng));
      }
    });

    test('rejects values just past the edges and NaN', () {
      for (final (lat, lng) in [
        (90.000001, 0.0),
        (-90.000001, 0.0),
        (0.0, 180.000001),
        (0.0, -180.000001),
        (double.nan, 0.0),
        (0.0, double.nan),
      ]) {
        expect(() => GeoPoint(lat, lng), throwsArgumentError);
      }
    });

    test('an out-of-range server value is a DecodeError', () {
      expect(
        () => parse('{"p": {"__type": "GeoPoint", "latitude": 91,'
                ' "longitude": 0}}')
            .require<GeoPoint>('p'),
        decodeError('p.latitude'),
      );
    });

    test('round trips', () {
      final p = GeoPoint(27.7, 85.3);
      expect(Json({'p': p.toJson()}).require<GeoPoint>('p'), p);
    });
  });

  group('Polygon', () {
    final open = [GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(1, 1)];

    test('a closed ring equals the open one and encodes open', () {
      final closed = Polygon([...open, GeoPoint(0, 0)]);
      expect(closed, Polygon(open));
      expect(closed.hashCode, Polygon(open).hashCode);
      expect(closed.toJson()['coordinates'], [
        [0, 0],
        [0, 1],
        [1, 1],
      ]);
    });

    test('needs 3 distinct vertices', () {
      expect(() => Polygon(open.sublist(0, 2)), throwsArgumentError);
      expect(() => Polygon([...open.sublist(0, 2), GeoPoint(0, 1)]),
          throwsArgumentError);
    });

    test('bad coordinates name the point', () {
      expect(
        () => parse('{"a": {"__type": "Polygon", "coordinates":'
                ' [[0, 0], [0, 1], [1, 200]]}}')
            .require<Polygon>('a'),
        decodeError('a.coordinates[2]'),
      );
    });
  });

  group('Bytes', () {
    test('round trips, including empty', () {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([0, 1, 2, 255])
      ]) {
        expect(Json({'b': encodeBytes(bytes)}).require<Uint8List>('b'), bytes);
      }
    });

    test('invalid base64 is a DecodeError', () {
      expect(
        () => parse('{"b": {"__type": "Bytes", "base64": "!!"}}')
            .require<Uint8List>('b'),
        decodeError('b.base64'),
      );
    });
  });

  test('ParseFile equality ignores the server-built url', () {
    const a = ParseFile(name: 'f.txt');
    const b = ParseFile(name: 'f.txt', url: 'http://x/f.txt');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const ParseFile(name: 'g.txt')));
  });

  group('Acl', () {
    final acl = Acl.publicRead()
        .withUser('u1', write: true)
        .withRole('admin', read: false, write: true);
    final wire = {
      '*': {'read': true},
      'u1': {'read': true, 'write': true},
      'role:admin': {'write': true},
    };

    test('builds public, user and role entries', () {
      expect(acl.public, (read: true, write: false));
      expect(acl.user('u1'), (read: true, write: true));
      expect(acl.role('admin'), (read: false, write: true));
      expect(acl.user('admin'), (read: false, write: false));
      expect(acl.toJson(), wire);
    });

    test('decodes all three kinds', () {
      final doc = Doc.decode(
        Json({
          'objectId': 'a',
          'createdAt': '2000-01-01T00:00:00.000Z',
          'updatedAt': '2000-01-01T00:00:00.000Z',
          'name': 'Ann',
          'ACL': wire,
        }),
        authorSchema,
      );
      expect(doc.acl, acl);
    });

    test('is immutable; revoking everything drops the entry', () {
      final base = Acl.publicRead();
      final more = base.withUser('u1');
      expect(base.user('u1'), (read: false, write: false));
      expect(more.withUser('u1', read: false), base);
      expect(more.withUser('u1', read: false).toJson(), base.toJson());
    });
  });

  group('Pointer', () {
    test('encodes with the schema class name', () {
      expect(const Pointer<Author>('a1').encode(authorSchema),
          {'__type': 'Pointer', 'className': 'Author', 'objectId': 'a1'});
    });

    test('a different class is a DecodeError', () {
      final j = parse('{"p": {"__type": "Pointer", "className": "Post",'
          ' "objectId": "a1"}}');
      expect(() => j.optPointer('p', authorSchema), decodeError('p.className'));
    });

    test('an error inside an included object names the path', () {
      final j = parse('{"p": {"__type": "Object", "className": "Author",'
          ' "objectId": "a1", "createdAt": "2000-01-01T00:00:00.000Z",'
          ' "updatedAt": "2000-01-01T00:00:00.000Z", "name": 7}}');
      expect(() => j.optPointer('p', authorSchema), decodeError('p.name'));
    });
  });

  test('Relation with a different class is a DecodeError', () {
    final j = parse('{"r": {"__type": "Relation", "className": "Post"}}');
    expect(() => j.relation('r', authorSchema), decodeError('r.className'));
  });
}
