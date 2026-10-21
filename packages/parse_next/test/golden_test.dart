import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parse_next/parse_next.dart';
import 'package:parse_next/src/client.dart';
import 'package:test/test.dart';

import 'fixtures.g.dart';
import 'models.dart';

const covered = {
  'batch_partial_failure.json',
  'batch_transaction_failure.json',
  'config.json',
  'create_all_fields.json',
  'create_null_fields.json',
  'error_101_acl_denied.json',
  'error_101_invalid_credentials.json',
  'error_101_missing.json',
  'error_137_duplicate.json',
  'error_137_function.json',
  'error_141_script_failed.json',
  'error_202_username_taken.json',
  'error_203_email_taken.json',
  'error_209_invalid_session.json',
  'error_252_unsupported_auth.json',
  'error_unauthorized.json',
  'file_upload.json',
  'function_call.json',
  'get_after_ops.mongo.json',
  'get_after_ops.postgres.json',
  'get_all_fields.json',
  'get_null_fields.mongo.json',
  'get_null_fields.postgres.json',
  'op_add.json',
  'op_add_relation.json',
  'op_add_unique.mongo.json',
  'op_add_unique.postgres.json',
  'op_delete.json',
  'op_increment.json',
  'op_remove.mongo.json',
  'op_remove.postgres.json',
  'op_remove_relation.json',
  'query_all_fields.json',
  'query_include.json',
  'query_related_to.json',
  'user_log_in.json',
  'user_log_in_with_existing.json',
  'user_log_in_with_new.json',
  'user_me.json',
  'user_sign_up.json',
};

Map<String, Object?> fixture(String name) {
  if (!covered.contains(name)) throw ArgumentError.value(name, 'name');
  return jsonDecode(fixtures[name]!) as Map<String, Object?>;
}

Json body(String name) => Json(
  (fixture(name)['request']! as Map<String, Object?>)['body']!
      as Map<String, Object?>,
);

Json response(String name) =>
    Json(fixture(name)['response']! as Map<String, Object?>);

Json firstResult(String name) => Json(
  (response(name)['results']! as List<Object?>).single! as Map<String, Object?>,
);

final epoch = DateTime.utc(2000);

final acl = const Acl()
    .withPublic()
    .withUser('obj0000001', write: true)
    .withRole('admin');

final file = ParseFile(
  name: 'file0001_hello.txt',
  url: 'http://parse.test/parse/files/parse-next-it/file0001_hello.txt',
);

/// The values sent in create_all_fields. [Post.area] is given open, as sent;
/// the server returns it closed, and [Polygon] drops the closing point, so a
/// decoded polygon equals this one and re-encodes to the request body.
Post sent({ParseFile? attachment}) => Post(
  title: 'Hello, wörld 👋',
  slug: 'hello-world',
  status: 'published',
  count: 20,
  ratio: 1.5,
  score: 2.0,
  published: true,
  publishedAt: DateTime.utc(2024, 1, 2, 3, 4, 5, 678),
  tags: ['a', 'b'],
  meta: Json({
    'list': [1, 'two'],
    'n': 1,
    'nested': {'b': true},
    'nil': null,
    's': 'x',
  }),
  location: GeoPoint(27.7, 85.3),
  area: Polygon([
    GeoPoint(0, 0),
    GeoPoint(0, 1),
    GeoPoint(1, 1),
    GeoPoint(1, 0),
  ]),
  attachment: attachment ?? file,
  data: Uint8List.fromList([0, 1, 2, 255]),
  author: const Pointer('obj0000003'),
  coauthors: const [Pointer('obj0000003'), Pointer('obj0000004')],
);

final stored = sent(attachment: file).view;

Json encodeWithAcl(Post post, Acl acl) =>
    Json({...postSchema.encode(post), 'ACL': acl.toJson()});

void main() {
  test('every fixture is covered', () {
    expect(fixtures.keys.toSet(), covered);
  });

  group('create', () {
    test('create_all_fields: encoding the values gives the request body', () {
      expect(encodeWithAcl(sent(), acl), body('create_all_fields.json'));
    });

    test('create_null_fields: null fields encode as null', () {
      final sentBody = body('create_null_fields.json');
      final encoded = postSchema.encode(const Post());
      // The capture leaves out slug (unique index) and area (a null Polygon
      // breaks later reads on Mongo); see parse_next_it/tool/capture.dart.
      expect(encoded.keys.toSet().difference(sentBody.keys.toSet()), {
        'slug',
        'area',
      });
      expect({for (final k in sentBody.keys) k: encoded[k]}, sentBody);
    });

    for (final (name, id) in [
      ('create_all_fields.json', 'obj0000005'),
      ('create_null_fields.json', 'obj0000006'),
    ]) {
      test('$name: response', () {
        final r = response(name);
        expect(r.require<String>('objectId'), id);
        expect(r.require<DateTime>('createdAt'), epoch);
      });
    }
  });

  group('get', () {
    for (final name in ['get_all_fields.json', 'query_all_fields.json']) {
      test('$name decodes every field type', () {
        final json = name.startsWith('query')
            ? firstResult(name)
            : response(name);
        final doc = Doc.decode(json, postSchema);
        expect(doc.id, 'obj0000005');
        expect(doc.createdAt, epoch);
        expect(doc.updatedAt, epoch);
        expect(doc.createdAt.isUtc, isTrue);
        expect(doc.acl, acl);
        expect(doc.data.view, stored);
        expect(doc.data.followers, isA<Relation<Author>>());
        expect(doc.data.author!.loaded, isNull);
        expect(doc.data.count, isA<int>());
        expect(doc.data.score, isA<double>());
      });
    }

    test('get_all_fields re-encodes to the create body', () {
      final doc = Doc.decode(response('get_all_fields.json'), postSchema);
      expect(encodeWithAcl(doc.data, doc.acl!), body('create_all_fields.json'));
    });

    for (final backend in ['mongo', 'postgres']) {
      test(
        'get_null_fields.$backend.json: null and absent both decode absent',
        () {
          final doc = Doc.decode(
            response('get_null_fields.$backend.json'),
            postSchema,
          );
          expect(doc.id, 'obj0000006');
          expect(doc.acl, isNull);
          expect(doc.data.view, const Post().view);
          expect(doc.data.followers, isA<Relation<Author>>());
        },
      );

      test('get_after_ops.$backend.json', () {
        final doc = Doc.decode(
          response('get_after_ops.$backend.json'),
          postSchema,
        );
        final expected = {...stored, 'count': 21, 'title': null};
        // Postgres reorders arrays after AddUnique (see PLAN.md).
        expect(doc.data.tags, unorderedEquals(['b', 'c', 'd']));
        expect({...doc.data.view, 'tags': null}, {...expected, 'tags': null});
      });
    }
  });

  group('query', () {
    test('query_include: included pointers carry the loaded Doc', () {
      final doc = Doc.decode(firstResult('query_include.json'), postSchema);
      expect(doc.data.view, stored);
      final author = doc.data.author!;
      expect(author.id, 'obj0000003');
      expect(author.loaded!.id, 'obj0000003');
      expect(author.loaded!.data.name, 'Ann');
      expect(author.loaded!.createdAt, epoch);
      expect(author.loaded!.updatedAt, epoch);
      expect(
        [for (final p in doc.data.coauthors!) (p.id, p.loaded!.data.name)],
        [('obj0000003', 'Ann'), ('obj0000004', 'Ben')],
      );
    });

    test('query_related_to: plain results decode as Doc', () {
      final doc = Doc.decode(
        firstResult('query_related_to.json'),
        authorSchema,
      );
      expect(doc.id, 'obj0000003');
      expect(doc.data.name, 'Ann');
      expect(doc.acl, isNull);
    });
  });

  test('file_upload: response is the File value without __type', () async {
    final f = fixture('file_upload.json');
    final req = f['request']! as Map<String, Object?>;
    final sent = <http.Request>[];
    final client = ParseClient(
      server: Uri.parse('http://parse.test/parse'),
      appId: 'parse-next-it',
      httpClient: MockClient((r) async {
        sent.add(r);
        return http.Response(jsonEncode(f['response']), f['status']! as int);
      }),
    );
    final uploaded = await client.uploadFile(
      utf8.encode(req['body']! as String),
      name: 'hello.txt',
      contentType: 'text/plain',
    );
    expect(sent.single.url.path, '/parse${req['path']}');
    expect(sent.single.body, req['body']);
    expect(uploaded, file);
    expect(uploaded.url, file.url);
  });

  // Request bodies here are __op ops, which are Phase 3; only the responses
  // are decoded.
  group('op responses', () {
    for (final (name, tags) in [
      ('op_add.json', ['a', 'b', 'c']),
      ('op_add_unique.mongo.json', ['a', 'b', 'c', 'd']),
      ('op_add_unique.postgres.json', ['a', 'd', 'c', 'b']),
      ('op_remove.mongo.json', ['b', 'c', 'd']),
      ('op_remove.postgres.json', ['d', 'c', 'b']),
    ]) {
      test(name, () {
        final r = response(name);
        expect(r.optList<String>('tags'), tags);
        expect(r.require<DateTime>('updatedAt'), epoch);
      });
    }

    test('op_increment.json', () {
      final r = response('op_increment.json');
      expect(r.require<int>('count'), 21);
      expect(r.require<DateTime>('updatedAt'), epoch);
    });

    for (final name in [
      'op_delete.json',
      'op_add_relation.json',
      'op_remove_relation.json',
    ]) {
      test(name, () {
        final r = response(name);
        expect(r.keys, ['updatedAt']);
        expect(r.require<DateTime>('updatedAt'), epoch);
      });
    }
  });

  group('errors', () {
    for (final (name, matcher) in [
      (
        'error_101_acl_denied.json',
        isA<ObjectNotFound>()
            .having((e) => e.code, 'code', 101)
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'Object not found.'),
      ),
      (
        'error_101_invalid_credentials.json',
        isA<InvalidCredentials>()
            .having((e) => e.code, 'code', 101)
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'Invalid username/password.'),
      ),
      (
        'error_101_missing.json',
        isA<ObjectNotFound>()
            .having((e) => e.code, 'code', 101)
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'Object not found.'),
      ),
      (
        'error_137_duplicate.json',
        isA<DuplicateValue>()
            .having((e) => e.code, 'code', 137)
            .having((e) => e.status, 'status', 400)
            .having(
              (e) => e.message,
              'message',
              'A duplicate value for a field with unique values was provided',
            ),
      ),
      (
        'error_137_function.json',
        isA<DuplicateValue>()
            .having((e) => e.code, 'code', 137)
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'failed with 137'),
      ),
      (
        'error_141_script_failed.json',
        isA<ScriptFailed>()
            .having((e) => e.code, 'code', 141)
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'fail was called'),
      ),
      (
        'error_202_username_taken.json',
        isA<UsernameTaken>()
            .having((e) => e.code, 'code', 202)
            .having((e) => e.status, 'status', 400)
            .having(
              (e) => e.message,
              'message',
              'Account already exists for this username.',
            ),
      ),
      (
        'error_203_email_taken.json',
        isA<EmailTaken>()
            .having((e) => e.code, 'code', 203)
            .having((e) => e.status, 'status', 400)
            .having(
              (e) => e.message,
              'message',
              'Account already exists for this email address.',
            ),
      ),
      (
        'error_209_invalid_session.json',
        isA<InvalidSession>()
            .having((e) => e.code, 'code', 209)
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'Invalid session token'),
      ),
      (
        'error_252_unsupported_auth.json',
        isA<OtherParseError>()
            .having((e) => e.code, 'code', 252)
            .having((e) => e.status, 'status', 400)
            .having(
              (e) => e.message,
              'message',
              'This authentication method is unsupported.',
            ),
      ),
      (
        'error_unauthorized.json',
        isA<Unauthorized>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.message, 'message', 'unauthorized'),
      ),
    ]) {
      test(name, () async {
        final f = fixture(name);
        final req = f['request']! as Map<String, Object?>;
        final client = ParseClient(
          server: Uri.parse('http://parse.test/parse'),
          appId: 'parse-next-it',
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(f['response']),
              f['status']! as int,
              // Express's res.json sets this; invalidRequest in
              // middlewares.js writes the unauthorized body with res.end.
              headers: name == 'error_unauthorized.json'
                  ? {}
                  : {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
        await expectLater(
          request(
            client,
            req['method']! as String,
            req['path']! as String,
            body: switch (req['body']) {
              final Map<String, Object?> b => Json(b),
              _ => null,
            },
          ),
          throwsA(matcher),
        );
      });
    }
  });

  test('function_call: a returned Parse Object decodes as Doc', () async {
    final f = fixture('function_call.json');
    final req = f['request']! as Map<String, Object?>;
    final sent = <http.Request>[];
    final client = ParseClient(
      server: Uri.parse('http://parse.test/parse'),
      appId: 'parse-next-it',
      httpClient: MockClient((r) async {
        sent.add(r);
        return http.Response(jsonEncode(f['response']), f['status']! as int);
      }),
    );
    final response = await client.callFunction('whoAmI', Json({}));
    expect(sent.single.url.path, '/parse${req['path']}');
    expect(jsonDecode(sent.single.body), req['body']);

    final doc = response.requireDoc('result', memberSchema);
    expect(doc.id, 'obj0000001');
    expect(doc.createdAt, epoch);
    expect(doc.updatedAt, epoch);
    expect(doc.acl, const Acl().withUser('obj0000001', write: true));
    expect(doc.data.username, 'alice');
  });

  test('config.json: the params, without the masterKeyOnly one', () async {
    final f = fixture('config.json');
    final client = ParseClient(
      server: Uri.parse('http://parse.test/parse'),
      appId: 'parse-next-it',
      httpClient: MockClient(
        (_) async =>
            http.Response(jsonEncode(f['response']), f['status']! as int),
      ),
    );
    final config = await client.config();
    expect(config.require<bool>('flag'), isTrue);
    expect(config.require<double>('limit'), 2.5);
    expect(config.require<String>('name'), 'x');
    expect(config.require<Json>('nested').requireList<Object>('list'), [
      1,
      'two',
    ]);
    expect(config, isNot(contains('secret')));
  });

  group('batch', () {
    late List<http.Request> sent;
    late ParseClient client;

    void replay(String name) {
      final f = fixture(name);
      sent = [];
      client = ParseClient(
        server: Uri.parse('http://parse.test/parse'),
        appId: 'parse-next-it',
        httpClient: MockClient((r) async {
          sent.add(r);
          return http.Response(jsonEncode(f['response']), f['status']! as int);
        }),
      );
    }

    void expectRequest(String name) {
      final req = fixture(name)['request']! as Map<String, Object?>;
      expect(sent.single.url.path, '/parse${req['path']}');
      expect(jsonDecode(sent.single.body), req['body']);
    }

    test('batch_partial_failure.json', () async {
      replay('batch_partial_failure.json');
      final authors = client.collection(authorSchema);
      final b = client.batch();
      final created = b.create(authors, const Author(name: 'Cy'));
      final missing = b.update(
        client.collection(postSchema),
        'doesNotExist',
        (o) => [o.count.set(1)],
      );
      final updated = b.update(
        authors,
        'obj0000003',
        (o) => [o.name.set('Ann')],
      );
      final deleted = b.delete(authors, 'obj0000004');
      await b.send();
      expectRequest('batch_partial_failure.json');

      final doc = (created.result as Ok<Doc<Author>>).value;
      expect(doc.id, 'obj0000008');
      expect(doc.createdAt, epoch);
      expect(doc.data.name, 'Cy');
      expect(
        (missing.result as Err<UpdateResult<Post>>).error,
        isA<ObjectNotFound>()
            .having((e) => e.message, 'message', 'Object not found.')
            .having((e) => e.status, 'status', 404),
      );
      expect(
        (updated.result as Ok<UpdateResult<Author>>).value.updatedAt,
        epoch,
      );
      expect(deleted.result, isA<Ok<void>>());
    });

    test('batch_transaction_failure.json', () async {
      replay('batch_transaction_failure.json');
      final b = client.batch();
      final created = b.create(
        client.collection(authorSchema),
        const Author(name: 'Cy'),
      );
      b.update(
        client.collection(postSchema),
        'doesNotExist',
        (o) => [o.count.set(1)],
      );
      await expectLater(
        b.send(transaction: true),
        throwsA(
          isA<OtherParseError>()
              .having((e) => e.code, 'code', 1)
              .having((e) => e.status, 'status', 500)
              .having((e) => e.message, 'message', 'Internal server error.'),
        ),
      );
      expectRequest('batch_transaction_failure.json');
      expect(() => created.result, throwsStateError);
    });
  });

  group('auth', () {
    Future<(Doc<Member>, http.Request)> replay(
      String name,
      Future<Doc<Member>> Function(Auth<Member> auth) call,
    ) async {
      final f = fixture(name);
      final sent = <http.Request>[];
      final client = ParseClient(
        server: Uri.parse('http://parse.test/parse'),
        appId: 'parse-next-it',
        httpClient: MockClient((r) async {
          sent.add(r);
          return http.Response(jsonEncode(f['response']), f['status']! as int);
        }),
      );
      final doc = await call(client.auth(memberSchema));
      final req = f['request']! as Map<String, Object?>;
      final only = sent.single;
      expect(only.method, req['method']);
      expect(only.url.path, '/parse${req['path']}');
      expect(only.body.isEmpty ? null : jsonDecode(only.body), req['body']);
      return (doc, only);
    }

    test('user_sign_up.json', () async {
      final (doc, _) = await replay(
        'user_sign_up.json',
        (a) => a.signUp(
          password: 'pw',
          user: const Member(username: 'carol', email: 'carol@example.test'),
        ),
      );
      expect(doc.id, 'obj0000007');
      expect(doc.createdAt, epoch);
      expect(doc.updatedAt, epoch);
      expect(doc.acl, isNull);
      expect(doc.data.email, 'carol@example.test');
      expect(doc.data.decodedKeys, isNot(contains('sessionToken')));
      expect(doc.data.decodedKeys, isNot(contains('password')));
    });

    test('user_log_in.json', () async {
      final (doc, _) = await replay(
        'user_log_in.json',
        (a) => a.logIn('carol', 'pw'),
      );
      expect(doc.id, 'obj0000007');
      expect(doc.data.username, 'carol');
      expect(doc.acl, const Acl().withUser('obj0000007', write: true));
      expect(doc.data.decodedKeys, isNot(contains('sessionToken')));
    });

    test('user_log_in_with_new.json: a 201 without updatedAt or ACL', () async {
      final (doc, _) = await replay(
        'user_log_in_with_new.json',
        (a) => a.logInWith('anonymous', {'id': 'capture-anonymous'}),
      );
      expect(doc.id, 'obj0000009');
      expect(doc.updatedAt, doc.createdAt);
      expect(doc.acl, isNull);
      expect(doc.data.username, 'user0001');
      expect(doc.data.decodedKeys, isNot(contains('sessionToken')));
    });

    test('user_log_in_with_existing.json', () async {
      final (doc, _) = await replay(
        'user_log_in_with_existing.json',
        (a) => a.logInWith('anonymous', {'id': 'capture-anonymous'}),
      );
      expect(doc.id, 'obj0000009');
      expect(doc.acl, const Acl().withUser('obj0000009', write: true));
      expect(doc.data.decodedKeys, isNot(contains('sessionToken')));
    });

    test('user_me.json', () async {
      final (doc, req) = await replay(
        'user_me.json',
        (a) => a.become('r:session0004'),
      );
      expect(req.headers['X-Parse-Session-Token'], 'r:session0004');
      expect(doc.id, 'obj0000007');
      expect(doc.data.decodedKeys, isNot(contains('sessionToken')));
    });
  });
}
