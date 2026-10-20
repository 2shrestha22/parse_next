import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/cloud.dart';
import 'package:parse_next_it/models/item.dart';
import 'package:parse_next_it/models/user.dart';
import 'package:test/test.dart';

import 'support.dart';

final at = DateTime.utc(2024, 1, 2, 3, 4, 5, 678);
final spot = GeoPoint(27.7, 85.3);
final area = Polygon([GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(1, 1)]);
final bytes = Uint8List.fromList([0, 1, 2, 255]);
const map = {
  'n': 1,
  's': 'wörld',
  'nested': {'b': true},
  'list': [1, 'two'],
  'nil': null,
};

Matcher decodeError(String key, String message) => isA<DecodeError>()
    .having((e) => e.key, 'key', key)
    .having((e) => e.message, 'message', message);

void main() {
  forEachBackend((backend) {
    ParseClient client() {
      final c = backend.client();
      addTearDown(c.close);
      return c;
    }

    late Cloud cloud;
    setUp(() => cloud = Cloud(client()));

    test('every parameter type round-trips as the same return type', () async {
      expect(await cloud.echoString(value: 'wörld 👋'), 'wörld 👋');
      expect(await cloud.echoInt(value: -7), -7);
      expect(await cloud.echoDouble(value: 2.0), isA<double>());
      expect(await cloud.echoNum(value: 1.5), 1.5);
      expect(await cloud.echoBool(value: false), isFalse);
      expect(await cloud.echoDate(value: at), at);
      expect(await cloud.echoEnum(value: Kind.green), Kind.green);
      expect(await cloud.echoStrings(value: ['a', 'b']), ['a', 'b']);
      expect(await cloud.echoInts(value: []), isEmpty);
      expect(await cloud.echoMap(value: map), map);
      expect((await cloud.echoPointer(value: const Pointer('u1'))).id, 'u1');
      expect(
        [
          for (final p in await cloud.echoPointers(
            value: const [Pointer('u1'), Pointer('u2')],
          ))
            p.id,
        ],
        ['u1', 'u2'],
      );
      expect(
        await cloud.echoFile(value: const ParseFile(name: 'a.txt')),
        const ParseFile(name: 'a.txt'),
      );
      expect(await cloud.echoGeoPoint(value: spot), spot);
      expect(await cloud.echoPolygon(value: area), area);
      expect(await cloud.echoBytes(value: bytes), bytes);
    });

    test('nullable parameter and return types round-trip a value', () async {
      expect(await cloud.echoNullableString(value: 's'), 's');
      expect(await cloud.echoNullableInt(value: 3), 3);
      expect(await cloud.echoNullableDouble(value: 0.25), 0.25);
      expect(await cloud.echoNullableNum(value: 4), 4);
      expect(await cloud.echoNullableBool(value: true), isTrue);
      expect(await cloud.echoNullableDate(value: at), at);
      expect(await cloud.echoNullableEnum(value: Kind.blue), Kind.blue);
      expect(await cloud.echoNullableStrings(value: ['x']), ['x']);
      expect(await cloud.echoNullableInts(value: [1, 2]), [1, 2]);
      expect(await cloud.echoNullableMap(value: map), map);
      expect(
        (await cloud.echoNullablePointer(value: const Pointer('u1')))!.id,
        'u1',
      );
      expect(
        (await cloud.echoNullablePointers(
          value: const [Pointer('u2')],
        ))!.single.id,
        'u2',
      );
      expect(
        await cloud.echoNullableFile(value: const ParseFile(name: 'b.txt')),
        const ParseFile(name: 'b.txt'),
      );
      expect(await cloud.echoNullableGeoPoint(value: spot), spot);
      expect(await cloud.echoNullablePolygon(value: area), area);
      expect(await cloud.echoNullableBytes(value: bytes), bytes);
    });

    test(
      'a null parameter is left out, so cloud code sees undefined',
      () async {
        expect(await cloud.paramKeys(b: 1), ['b']);
        expect(await cloud.paramKeys(a: 'x', b: 1, c: at), ['a', 'b', 'c']);

        // Each echo then returns undefined, which leaves `result` out.
        final results = await Future.wait<Object?>([
          cloud.echoNullableString(),
          cloud.echoNullableInt(),
          cloud.echoNullableDouble(),
          cloud.echoNullableNum(),
          cloud.echoNullableBool(),
          cloud.echoNullableDate(),
          cloud.echoNullableEnum(),
          cloud.echoNullableStrings(),
          cloud.echoNullableInts(),
          cloud.echoNullableMap(),
          cloud.echoNullablePointer(),
          cloud.echoNullablePointers(),
          cloud.echoNullableFile(),
          cloud.echoNullableGeoPoint(),
          cloud.echoNullablePolygon(),
          cloud.echoNullableBytes(),
        ]);
        expect(results, everyElement(isNull));
      },
    );

    test('void ignores the result', () async {
      await cloud.ping();
    });

    test('a non-nullable return without a result is DecodeError', () async {
      await expectLater(
        cloud.returnsNull(),
        throwsA(decodeError('result', 'missing')),
      );
      await expectLater(
        cloud.returnsUndefined(),
        throwsA(decodeError('result', 'missing')),
      );
    });

    test('a thrown Error is ScriptFailed with its message', () async {
      await expectLater(
        cloud.fail(),
        throwsA(
          isA<ScriptFailed>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message', 'fail was called'),
        ),
      );
    });

    test('a thrown Parse.Error keeps its code', () async {
      for (final (code, matcher) in [
        (101, isA<ObjectNotFound>().having((e) => e.status, 'status', 404)),
        (137, isA<DuplicateValue>().having((e) => e.status, 'status', 400)),
        (141, isA<ScriptFailed>().having((e) => e.status, 'status', 400)),
        (
          119,
          isA<OtherParseError>()
              .having((e) => e.code, 'code', 119)
              .having((e) => e.status, 'status', 400),
        ),
      ]) {
        await expectLater(
          cloud.failWithCode(code: code),
          throwsA(
            matcher.having((e) => e.message, 'message', 'failed with $code'),
          ),
        );
      }
    });

    test('the session reaches the function as request.user', () async {
      expect(await cloud.whoAmI(), isNull);
      await expectLater(
        cloud.requireUser(),
        throwsA(decodeError('result', 'missing')),
      );

      final c = client();
      final name = 'cloud-${DateTime.now().microsecondsSinceEpoch}';
      final user = await c
          .auth(users)
          .signUp(
            password: 'pw',
            user: User(username: name, karma: 5),
          );
      final me = (await Cloud(c).whoAmI())!;
      expect(me.id, user.id);
      expect(me.data.username, name);
      expect(me.data.karma, 5);
      expect(me.createdAt, user.createdAt);
      expect((await Cloud(c).requireUser()).id, user.id);
    });

    test('Parse Objects from a cloud query decode as Doc', () async {
      final a = await backend.signUp('cloud-a', {'karma': 1});
      final b = await backend.signUp('cloud-b');
      final names = [
        for (final u in [a, b])
          (await backend.rest(
                'GET',
                '/classes/_User/${u.id}',
                master: true,
              ))['username']!
              as String,
      ];

      final found = await cloud.findUsers(usernames: names);
      expect([for (final d in found) d.id], [a.id, b.id]);
      expect([for (final d in found) d.data.karma], [1, null]);
      expect(found.first.acl!.user(a.id), (read: true, write: true));
      expect(found.first.createdAt.isUtc, isTrue);

      expect(await cloud.findUsersOrNull(), isNull);
      expect(
        [
          for (final d in (await cloud.findUsersOrNull(usernames: names))!)
            d.id,
        ],
        [a.id, b.id],
      );
    });
  });
}

const users = $UserSchema();
