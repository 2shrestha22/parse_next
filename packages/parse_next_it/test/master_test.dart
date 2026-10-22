import 'dart:convert';
import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/installation.dart';
import 'package:parse_next_it/models/tally.dart';
import 'package:parse_next_it/models/user.dart';
import 'package:test/test.dart';

import 'support.dart';

const tallies = $TallySchema();
const installations = $InstallationSchema();

void main() {
  forEachBackend((backend) {
    late ParseClient admin;
    late ParseClient anyone;

    setUpAll(() async {
      await backend.resetClass('Tally', {
        'tag': {'type': 'String'},
        'n': {'type': 'Number'},
      });
      admin = backend.client(master: true);
      anyone = backend.client();
      for (final (tag, n) in [('a', 1), ('a', 2), ('b', 3), ('c', 4)]) {
        await admin.collection(tallies).create(Tally(tag: tag, n: n));
      }
    });

    tearDownAll(() {
      admin.close();
      anyone.close();
    });

    String unique(String name) =>
        '$name${DateTime.now().microsecondsSinceEpoch}';

    Future<V> eventually<V>(
      Future<V> Function() read,
      bool Function(V) done,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        final v = await read();
        if (done(v) || DateTime.now().isAfter(deadline)) return v;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    test('reads and writes past an ACL that lets no one in', () async {
      final doc = await admin
          .collection(tallies)
          .create(const Tally(tag: 'private', n: 0), acl: const Acl());
      await expectLater(
        anyone.collection(tallies).get(doc.id),
        throwsA(isA<ObjectNotFound>()),
      );
      await admin.collection(tallies).update(doc.id, (o) => [o.n.set(1)]);
      expect((await admin.collection(tallies).get(doc.id)).data.n, 1);
      await admin.collection(tallies).delete(doc.id);
    });

    test('acts as no user, though a session is set', () async {
      final user = await backend.signUp('master');
      final c = backend.client(master: true);
      addTearDown(c.close);
      await c.auth(const $UserSchema()).become(user.token);
      expect((await c.callFunction('whoAmI', Json({})))['result'], isNull);
    });

    test('aggregate runs the pipeline', () async {
      final rows = await admin.collection(tallies).aggregate([
        {
          r'$match': {
            'n': {r'$gt': 1},
          },
        },
        {
          r'$group': {
            '_id': r'$tag',
            'total': {r'$sum': r'$n'},
          },
        },
      ]);
      expect(
        {for (final r in rows) r['objectId']: r['total']},
        {'a': 2, 'b': 3, 'c': 4},
      );
    });

    test('distinct applies the where condition', () async {
      final values = await admin
          .collection(tallies)
          .where((f) => f.n.lte(3))
          .distinct((f) => f.tag);
      expect(values, unorderedEquals(['a', 'b']));
    });

    test('explain returns the database plan', () async {
      final plan = await admin
          .collection(tallies)
          .where((f) => f.tag.eq('a'))
          .explain();
      expect(
        plan,
        backend.isPostgres ? isA<List<Object?>>() : isA<Map<String, Object?>>(),
      );
    });

    test('without the master key, aggregate is Unauthorized', () async {
      await expectLater(
        anyone.collection(tallies).query().distinct((f) => f.tag),
        throwsA(isA<Unauthorized>()),
      );
    });

    test('saveConfig sets params and which are master-only', () async {
      final open = unique('open');
      final secret = unique('secret');
      await admin.saveConfig(
        {open: 1, secret: DateTime.utc(2020)},
        masterKeyOnly: {secret},
      );
      final all = await admin.config();
      expect(all[open], 1);
      expect(all[secret], {
        '__type': 'Date',
        'iso': '2020-01-01T00:00:00.000Z',
      });
      final public = await anyone.config();
      expect(public[open], 1);
      expect(public.containsKey(secret), isFalse);

      await admin.saveConfig({secret: 2});
      expect((await anyone.config())[secret], 2);
    });

    test('deleteFile removes the stored file', () async {
      final file = await admin.uploadFile(
        Uint8List.fromList(utf8.encode('bye')),
        name: 'bye.txt',
        contentType: 'text/plain',
      );
      expect(utf8.decode(await admin.downloadFile(file)), 'bye');
      await admin.deleteFile(file);
      await expectLater(
        admin.downloadFile(file),
        throwsA(isA<OtherParseError>().having((e) => e.status, 'status', 404)),
      );
    });

    test('startJob runs the job and returns its status id', () async {
      final id = await admin.startJob('echoJob', Json({'x': 1}));
      final row = await eventually(
        () => backend.rest('GET', '/classes/_JobStatus/$id', master: true),
        (r) => r['status'] != 'running',
      );
      expect(row['status'], 'succeeded');
      expect(row['jobName'], 'echoJob');
      expect(
        (await backend.rest(
          'POST',
          '/functions/jobParams',
          body: {},
        ))['result'],
        {'x': 1},
      );
    });

    group('push', () {
      Future<String> install(String channel) async {
        final token = unique('token');
        await backend.rest(
          'POST',
          '/installations',
          master: true,
          body: {
            'deviceType': 'android',
            'deviceToken': token,
            'installationId': unique('iid'),
            'channels': [channel],
          },
        );
        return token;
      }

      Future<List<String>> reached(Map<String, Object?> data) async {
        final sent =
            (await backend.rest(
                  'POST',
                  '/functions/sentPushes',
                  body: {},
                ))['result']!
                as List<Object?>;
        return [
          for (final p in sent.cast<Map<String, Object?>>())
            if (jsonEncode(p['data']) == jsonEncode(data))
              ...(p['tokens']! as List<Object?>).cast<String>(),
        ];
      }

      test('to channels', () async {
        final channel = unique('news');
        final token = await install(channel);
        await install(unique('other'));
        final data = {'alert': unique('hi')};
        final id = await admin.push(data, channels: [channel]);
        expect(
          (await backend.rest(
            'GET',
            '/classes/_PushStatus/$id',
            master: true,
          ))['objectId'],
          id,
        );
        expect(await eventually(() => reached(data), (t) => t.isNotEmpty), [
          token,
        ]);
      });

      test('to an installation query', () async {
        final token = await install(unique('any'));
        final data = {'alert': unique('hey')};
        await admin.push(
          data,
          where: admin
              .collection(installations)
              .where((f) => f.deviceToken.eq(token)),
        );
        expect(await eventually(() => reached(data), (t) => t.isNotEmpty), [
          token,
        ]);
      });
    });

    test('schema create, update, purge and delete', () async {
      final name = unique('Made');
      final schema = admin.schema(name);
      await schema.create(
        fields: {
          'title': {'type': 'String'},
          'owner': {'type': 'Pointer', 'targetClass': '_User'},
        },
        indexes: {
          'by_title': {'title': 1},
        },
      );
      var got = await schema.get();
      expect(got.require<Json>('fields').keys, containsAll(['title', 'owner']));
      expect(got.require<Json>('indexes').keys, contains('by_title'));
      expect([
        for (final s in await admin.schemas()) s['className'],
      ], contains(name));

      await schema.update(
        fields: {
          'owner': null,
          'count': {'type': 'Number', 'defaultValue': 0},
        },
        indexes: {'by_title': null},
      );
      got = await schema.get();
      expect(got.require<Json>('fields').keys, isNot(contains('owner')));
      expect(got.require<Json>('fields')['count'], {
        'type': 'Number',
        'defaultValue': 0,
      });
      expect(got.opt<Json>('indexes')?.keys ?? [], isNot(contains('by_title')));

      await backend.rest(
        'POST',
        '/classes/$name',
        master: true,
        body: {'title': 't'},
      );
      await expectLater(
        schema.delete(),
        throwsA(isA<OtherParseError>().having((e) => e.code, 'code', 255)),
      );
      await schema.purge();
      await schema.delete();
      await expectLater(
        schema.get(),
        throwsA(isA<OtherParseError>().having((e) => e.code, 'code', 103)),
      );
    });
  });
}
