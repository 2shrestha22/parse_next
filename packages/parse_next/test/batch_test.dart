import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parse_next/parse_next.dart';
import 'package:test/test.dart';

import 'models.dart';

const createdAt = '2024-01-02T03:04:05.678Z';
const updatedAt = '2024-02-03T04:05:06.789Z';

final class Server {
  Server(this.response, {this.status = 200, this.server = 'http://h/parse'});

  final Object? response;
  final int status;
  final String server;
  final requests = <http.Request>[];
  late final client = ParseClient(
    server: Uri.parse(server),
    appId: 'app',
    httpClient: MockClient((r) async {
      requests.add(r);
      return http.Response(jsonEncode(response), status);
    }),
  );
  late final posts = client.collection(postSchema);

  http.Request get only => requests.single;
}

void main() {
  group('send', () {
    test('one POST /batch with every item under the mount path', () async {
      final s = Server([
        {
          'success': {'objectId': 'n1', 'createdAt': createdAt},
        },
        {
          'success': {'updatedAt': updatedAt},
        },
        {
          'success': {'updatedAt': updatedAt},
        },
        {'success': <String, Object?>{}},
      ]);
      final b = s.client.batch();
      b.create(s.posts, const Post(title: 't'));
      b.update(s.posts, 'a/1', (o) => [o.count.increment(1)]);
      b.replace(s.posts, 'p2', const Post(title: 'r'));
      b.delete(s.posts, 'p3');
      await b.send();

      expect(s.only.method, 'POST');
      expect(s.only.url.toString(), 'http://h/parse/batch');
      expect(s.only.headers['Content-Type'], 'application/json');
      final replaced = {
        for (final k in postSchema.encode(const Post()).keys)
          k: {'__op': 'Delete'},
        'title': 'r',
      };
      expect(jsonDecode(s.only.body), {
        'requests': [
          {
            'method': 'POST',
            'path': '/parse/classes/Post',
            'body': {'title': 't'},
          },
          {
            'method': 'PUT',
            'path': '/parse/classes/Post/a%2F1',
            'body': {
              'count': {'__op': 'Increment', 'amount': 1},
            },
          },
          {'method': 'PUT', 'path': '/parse/classes/Post/p2', 'body': replaced},
          {'method': 'DELETE', 'path': '/parse/classes/Post/p3'},
        ],
      });
    });

    test('transaction: true is sent only when asked for', () async {
      final s = Server([
        {
          'success': {'updatedAt': updatedAt},
        },
      ]);
      final b = s.client.batch()..update(s.posts, 'p', (o) => [o.count.set(1)]);
      await b.send(transaction: true);
      expect(
        (jsonDecode(s.only.body) as Map<String, Object?>)['transaction'],
        true,
      );
      expect(s.only.persistentConnection, isFalse);
    });

    test('a batch without transaction keeps its connection', () async {
      final s = Server([
        {
          'success': {'updatedAt': updatedAt},
        },
      ]);
      final b = s.client.batch()..update(s.posts, 'p', (o) => [o.count.set(1)]);
      await b.send();
      expect(s.only.persistentConnection, isTrue);
    });

    for (final (server, path) in [
      ('http://h', '/classes/Post'),
      ('http://h/', '/classes/Post'),
      ('http://h/a/parse/', '/a/parse/classes/Post'),
    ]) {
      test('item path for server $server', () async {
        final s = Server(server: server, [
          {'success': <String, Object?>{}},
        ]);
        await (s.client.batch()..delete(s.posts, 'x')).send();
        final items =
            (jsonDecode(s.only.body) as Map<String, Object?>)['requests']!
                as List<Object?>;
        expect((items.single! as Map<String, Object?>)['path'], '$path/x');
      });
    }
  });

  group('results', () {
    test('each handle gets its own item, Ok or Err', () async {
      final s = Server([
        {
          'success': {
            'objectId': 'n1',
            'createdAt': createdAt,
            'title': 'T',
            'count': {'__op': 'Delete'},
          },
        },
        {
          'error': {'code': 101, 'error': 'Object not found.'},
        },
        {
          'success': {'updatedAt': updatedAt},
        },
        {'success': <String, Object?>{}},
        {
          'error': {'code': 137, 'error': 'dup'},
        },
        {
          'error': {'code': 119, 'error': 'nope'},
        },
      ]);
      final b = s.client.batch();
      final c = b.create(s.posts, const Post(title: 't', count: 3));
      final u = b.update(s.posts, 'gone', (o) => [o.count.increment(1)]);
      final r = b.replace(s.posts, 'p2', const Post(title: 'r'));
      final d = b.delete(s.posts, 'p3');
      final dup = b.create(s.posts, const Post(slug: 's'));
      final other = b.delete(s.posts, 'p4');
      await b.send();

      final doc = (c.result as Ok<Doc<Post>>).value;
      expect(doc.id, 'n1');
      expect(doc.createdAt, DateTime.parse(createdAt));
      expect(doc.updatedAt, DateTime.parse(createdAt));
      // The trigger's changes are merged, and a field it unset is absent.
      expect(doc.data.title, 'T');
      expect(doc.data.count, isNull);

      expect(
        (u.result as Err<DateTime>).error,
        isA<ObjectNotFound>()
            .having((e) => e.message, 'message', 'Object not found.')
            .having((e) => e.status, 'status', 404),
      );
      expect((r.result as Ok<DateTime>).value, DateTime.parse(updatedAt));
      expect(d.result, isA<Ok<void>>());
      expect(
        (dup.result as Err<Doc<Post>>).error,
        isA<DuplicateValue>().having((e) => e.status, 'status', 400),
      );
      expect(
        (other.result as Err<void>).error,
        isA<OtherParseError>()
            .having((e) => e.code, 'code', 119)
            .having((e) => e.message, 'message', 'nope')
            .having((e) => e.status, 'status', 400),
      );
      expect(s.requests, hasLength(1));
    });

    test('an item that does not decode is Err(DecodeError)', () async {
      final s = Server([
        {
          'success': {'updatedAt': 'not a date'},
        },
        {'neither': true},
        {
          'success': {'updatedAt': updatedAt},
        },
      ]);
      final b = s.client.batch();
      final bad = b.update(s.posts, 'a', (o) => [o.count.set(1)]);
      final odd = b.update(s.posts, 'b', (o) => [o.count.set(1)]);
      final good = b.update(s.posts, 'c', (o) => [o.count.set(1)]);
      await b.send();
      expect(
        (bad.result as Err<DateTime>).error,
        isA<DecodeError>().having((e) => e.key, 'key', '[0].updatedAt'),
      );
      expect(
        (odd.result as Err<DateTime>).error,
        isA<DecodeError>().having((e) => e.key, 'key', '[1]'),
      );
      expect(good.result, isA<Ok<DateTime>>());
    });

    test('a result count that does not match throws DecodeError', () async {
      final s = Server(<Object?>[]);
      final b = s.client.batch()..delete(s.posts, 'a');
      await expectLater(b.send(), throwsA(isA<DecodeError>()));
    });

    test('a failed request throws from send and sets no result', () async {
      final s = Server(status: 500, {
        'code': 1,
        'message': 'Internal server error.',
      });
      final b = s.client.batch();
      final d = b.delete(s.posts, 'a');
      await expectLater(
        b.send(transaction: true),
        throwsA(
          isA<OtherParseError>()
              .having((e) => e.code, 'code', 1)
              .having((e) => e.status, 'status', 500),
        ),
      );
      expect(() => d.result, throwsStateError);
      expect(b.send, throwsStateError);
      expect(s.requests, hasLength(1));
    });

    test('a non-list success body is OtherParseError', () async {
      final s = Server(<String, Object?>{});
      final b = s.client.batch()..delete(s.posts, 'a');
      await expectLater(b.send(), throwsA(isA<OtherParseError>()));
    });
  });

  group('misuse sends nothing', () {
    test('reading a result before send is a StateError', () {
      final s = Server(<Object?>[]);
      final d = s.client.batch().delete(s.posts, 'a');
      expect(() => d.result, throwsStateError);
      expect(s.requests, isEmpty);
    });

    test('an empty batch is an ArgumentError', () {
      final s = Server(<Object?>[]);
      expect(s.client.batch().send, throwsArgumentError);
      expect(s.requests, isEmpty);
    });

    test('adding after send, or sending twice, is a StateError', () async {
      final s = Server([
        {'success': <String, Object?>{}},
      ]);
      final b = s.client.batch()..delete(s.posts, 'a');
      await b.send();
      expect(() => b.delete(s.posts, 'b'), throwsStateError);
      expect(() => b.create(s.posts, const Post()), throwsStateError);
      expect(
        () => b.update(s.posts, 'b', (o) => [o.count.set(1)]),
        throwsStateError,
      );
      expect(() => b.replace(s.posts, 'b', const Post()), throwsStateError);
      expect(b.send, throwsStateError);
      expect(s.requests, hasLength(1));
    });

    test('update with no ops or two ops on one key throws', () {
      final s = Server(<Object?>[]);
      final b = s.client.batch();
      expect(() => b.update(s.posts, 'a', (o) => []), throwsArgumentError);
      expect(
        () => b.update(s.posts, 'a', (o) => [o.count.set(1), o.count.set(2)]),
        throwsArgumentError,
      );
      expect(b.send, throwsArgumentError);
      expect(s.requests, isEmpty);
    });

    test('a collection of another client is an ArgumentError', () {
      final a = Server(<Object?>[]);
      final b = Server(<Object?>[]);
      expect(() => a.client.batch().delete(b.posts, 'x'), throwsArgumentError);
      expect([...a.requests, ...b.requests], isEmpty);
    });
  });

  group('uploadFile', () {
    test('sends the raw bytes with the content type', () async {
      final s = Server({
        'name': 'abc_a b+c.png',
        'url': 'http://h/parse/files/app/abc_a%20b%2Bc.png',
      });
      final bytes = Uint8List.fromList([0, 1, 2, 255, 0x80]);
      final file = await s.client.uploadFile(
        bytes,
        name: 'a b+c.png',
        contentType: 'image/png',
      );
      expect(s.only.method, 'POST');
      expect(s.only.url.toString(), 'http://h/parse/files/a%20b%2Bc.png');
      expect(s.only.headers['Content-Type'], 'image/png');
      expect(s.only.headers['X-Parse-Application-Id'], 'app');
      expect(s.only.bodyBytes, bytes);
      expect(file.name, 'abc_a b+c.png');
      expect(file.url, 'http://h/parse/files/app/abc_a%20b%2Bc.png');
    });

    test('sends the stored session', () async {
      final store = InMemorySessionStore();
      await store.write(
        jsonEncode({
          'sessionToken': 'r:t',
          'user': {
            'objectId': 'u',
            'createdAt': createdAt,
            'updatedAt': createdAt,
          },
        }),
      );
      final requests = <http.Request>[];
      final client = ParseClient(
        server: Uri.parse('http://h/parse'),
        appId: 'app',
        sessions: store,
        httpClient: MockClient((r) async {
          requests.add(r);
          return http.Response(jsonEncode({'name': 'n', 'url': 'u'}), 201);
        }),
      );
      await client.uploadFile(
        Uint8List.fromList([1]),
        name: 'n',
        contentType: 'text/plain',
      );
      expect(requests.single.headers['X-Parse-Session-Token'], 'r:t');
    });

    test('a 122 invalid name is OtherParseError', () async {
      final s = Server(status: 400, {
        'code': 122,
        'error': 'Filename contains invalid characters.',
      });
      await expectLater(
        s.client.uploadFile(
          Uint8List.fromList([1]),
          name: '?',
          contentType: 'text/plain',
        ),
        throwsA(isA<OtherParseError>().having((e) => e.code, 'code', 122)),
      );
    });
  });
}
