// The fake LiveQuery server is a dart:io HttpServer.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:fake_async/fake_async.dart';
import 'package:parse_next/parse_next.dart';
import 'package:test/test.dart';

import 'models.dart';

const at = '2024-01-02T03:04:05.678Z';

Map<String, Object?> object(String id, [String title = 't']) => {
  'className': 'Post',
  'objectId': id,
  'createdAt': at,
  'updatedAt': at,
  'title': title,
};

final class Connection {
  Connection(this.socket) : messages = StreamQueue(socket.cast<String>());

  final WebSocket socket;
  final StreamQueue<String> messages;

  Future<String> next() => messages.next;
  Future<Map<String, Object?>> nextJson() async =>
      jsonDecode(await next()) as Map<String, Object?>;
  void send(Map<String, Object?> message) => socket.add(jsonEncode(message));

  /// Reads the connect frame and answers it.
  Future<void> accept() async {
    expect((await nextJson())['op'], 'connect');
    send({'op': 'connected', 'clientId': 'c'});
  }

  Future<int> subscribed() async {
    final m = await nextJson();
    expect(m['op'], 'subscribe');
    final id = m['requestId']! as int;
    send({'op': 'subscribed', 'clientId': 'c', 'requestId': id});
    return id;
  }
}

final class FakeServer {
  FakeServer._(this._http);

  static Future<FakeServer> start() async {
    final server = FakeServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._http.listen((request) async {
      server.paths.add(request.uri.path);
      server._connections.add(
        Connection(await WebSocketTransformer.upgrade(request)),
      );
    });
    return server;
  }

  final HttpServer _http;
  final _connections = StreamController<Connection>();
  late final connections = StreamQueue(_connections.stream);
  final paths = <String>[];

  Uri get url => Uri.parse('http://127.0.0.1:${_http.port}/parse');

  Future<void> close() => _http.close(force: true);
}

Future<ParseClient> client(
  FakeServer server, {
  String? clientKey,
  String? token,
}) async {
  final sessions = InMemorySessionStore();
  if (token != null) {
    await sessions.write(
      jsonEncode({'sessionToken': token, 'user': <String, Object?>{}}),
    );
  }
  final c = ParseClient(
    server: server.url,
    appId: 'app',
    clientKey: clientKey,
    sessions: sessions,
  );
  addTearDown(c.close);
  return c;
}

/// A [StreamQueue] listens only on its first request, and the socket opens
/// only once the stream is listened to.
StreamQueue<T> started<T>(Stream<T> stream) {
  final queue = StreamQueue(stream);
  unawaited(queue.hasNext);
  return queue;
}

void main() {
  late FakeServer server;
  setUp(() async {
    server = await FakeServer.start();
    addTearDown(server.close);
  });

  test('connect, subscribe and unsubscribe send exact frames', () async {
    final c = await client(server, clientKey: 'ck', token: 'r:tok');
    final posts = c.collection(postSchema);
    final events = started(posts.where((f) => f.title.eq('a')).live());

    final conn = await server.connections.next;
    expect(server.paths, ['/parse']);
    expect(
      await conn.next(),
      '{"op":"connect","applicationId":"app","clientKey":"ck"}',
    );
    conn.send({'op': 'connected', 'clientId': 'c'});
    expect(
      await conn.next(),
      '{"op":"subscribe","requestId":1,'
      '"query":{"className":"Post","where":{"title":"a"}},'
      '"sessionToken":"r:tok"}',
    );
    conn.send({'op': 'subscribed', 'clientId': 'c', 'requestId': 1});
    expect(await events.next, isA<Subscribed<Post>>());

    for (final op in ['create', 'enter', 'update', 'leave', 'delete']) {
      conn.send({
        'op': op,
        'clientId': 'c',
        'requestId': 1,
        'object': object('o-$op', op),
      });
    }
    final got = [for (var i = 0; i < 5; i++) await events.next];
    expect(
      [for (final e in got) e.runtimeType.toString()],
      [
        'Created<Post>',
        'Entered<Post>',
        'Updated<Post>',
        'Left<Post>',
        'Deleted<Post>',
      ],
    );
    expect((got.first as Created<Post>).doc.id, 'o-create');
    expect((got.last as Deleted<Post>).doc.data.title, 'delete');

    await events.cancel();
    expect(await conn.next(), '{"op":"unsubscribe","requestId":1}');
    expect(await conn.messages.hasNext, isFalse);
  });

  test('no client key or session leaves both out', () async {
    final c = await client(server);
    final sub = c.collection(postSchema).query().live().listen(null);
    addTearDown(sub.cancel);
    final conn = await server.connections.next;
    expect(await conn.next(), '{"op":"connect","applicationId":"app"}');
    conn.send({'op': 'connected', 'clientId': 'c'});
    expect(
      await conn.next(),
      '{"op":"subscribe","requestId":1,'
      '"query":{"className":"Post","where":{}}}',
    );
  });

  test('liveQueryServer overrides the URL', () async {
    final c = ParseClient(
      server: Uri.parse('https://elsewhere.test/parse'),
      appId: 'app',
      liveQueryServer: server.url.replace(scheme: 'ws', path: '/lq'),
    );
    addTearDown(c.close);
    expect(
      ParseClient(
        server: Uri.parse('https://h.test/parse'),
        appId: 'a',
      ).liveQueryServer,
      Uri.parse('wss://h.test/parse'),
    );
    final sub = c.collection(postSchema).query().live().listen(null);
    addTearDown(sub.cancel);
    await server.connections.next;
    expect(server.paths, ['/lq']);
  });

  test('two subscriptions share one socket', () async {
    final c = await client(server);
    final posts = c.collection(postSchema);
    final a = started(posts.where((f) => f.title.eq('a')).live());
    final b = started(posts.where((f) => f.title.eq('b')).live());
    final conn = await server.connections.next;
    await conn.accept();
    final ids = {await conn.subscribed(), await conn.subscribed()};
    expect(ids, {1, 2});
    expect(await a.next, isA<Subscribed<Post>>());
    expect(await b.next, isA<Subscribed<Post>>());

    conn
      ..send({
        'op': 'create',
        'clientId': 'c',
        'requestId': 2,
        'object': object('in-b'),
      })
      ..send({
        'op': 'create',
        'clientId': 'c',
        'requestId': 1,
        'object': object('in-a'),
      });
    expect(((await a.next) as Created<Post>).doc.id, 'in-a');
    expect(((await b.next) as Created<Post>).doc.id, 'in-b');

    await a.cancel();
    expect(await conn.next(), '{"op":"unsubscribe","requestId":1}');
    conn.send({
      'op': 'update',
      'clientId': 'c',
      'requestId': 2,
      'object': object('still-b'),
    });
    expect(((await b.next) as Updated<Post>).doc.id, 'still-b');
    await b.cancel();
    expect(await conn.next(), '{"op":"unsubscribe","requestId":2}');
    expect(await conn.messages.hasNext, isFalse);
  });

  test('a reconnect resubscribes and emits Subscribed again', () async {
    final c = await client(server, token: 'r:tok');
    final events = started(
      c.collection(postSchema).where((f) => f.title.eq('a')).live(),
    );
    final first = await server.connections.next;
    await first.accept();
    await first.subscribed();
    expect(await events.next, isA<Subscribed<Post>>());
    await first.socket.close();

    final second = await server.connections.next;
    expect(await second.next(), '{"op":"connect","applicationId":"app"}');
    second.send({'op': 'connected', 'clientId': 'c2'});
    expect(
      await second.next(),
      '{"op":"subscribe","requestId":1,'
      '"query":{"className":"Post","where":{"title":"a"}},'
      '"sessionToken":"r:tok"}',
    );
    second.send({'op': 'subscribed', 'clientId': 'c2', 'requestId': 1});
    expect(await events.next, isA<Subscribed<Post>>());
    second.send({
      'op': 'create',
      'clientId': 'c2',
      'requestId': 1,
      'object': object('after'),
    });
    expect(((await events.next) as Created<Post>).doc.id, 'after');
    await events.cancel();
  });

  test(
    'a subscription first confirmed after a reconnect gets one Subscribed',
    () async {
      final c = await client(server);
      final events = started(c.collection(postSchema).query().live());
      final first = await server.connections.next;
      await first.accept();
      await first.nextJson();
      await first.socket.close();

      final second = await server.connections.next;
      await second.accept();
      await second.subscribed();
      second.send({
        'op': 'create',
        'clientId': 'c',
        'requestId': 1,
        'object': object('x'),
      });
      expect(await events.next, isA<Subscribed<Post>>());
      expect(await events.next, isA<Created<Post>>());
      await events.cancel();
    },
  );

  test('an error op is the mapped exception and ends the stream', () async {
    final c = await client(server);
    final posts = c.collection(postSchema);
    final bad = started(posts.where((f) => f.title.matches('(')).live());
    final good = started(posts.query().live());
    final conn = await server.connections.next;
    await conn.accept();
    await conn.nextJson();
    await conn.subscribed();
    conn.send({
      'op': 'error',
      'error': 'Invalid regular expression',
      'code': 102,
      'reconnect': false,
      'requestId': 1,
    });
    await expectLater(
      bad.next,
      throwsA(
        isA<OtherParseError>()
            .having((e) => e.code, 'code', 102)
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'Invalid regular expression'),
      ),
    );
    expect(await bad.hasNext, isFalse);
    expect(await conn.next(), '{"op":"unsubscribe","requestId":1}');

    conn.send({
      'op': 'error',
      'error': 'Invalid session token',
      'code': 209,
      'reconnect': false,
      'requestId': 2,
    });
    expect(await good.next, isA<Subscribed<Post>>());
    await expectLater(good.next, throwsA(isA<InvalidSession>()));
  });

  test('an error before connected ends every stream', () async {
    final c = await client(server);
    final events = started(c.collection(postSchema).query().live());
    final conn = await server.connections.next;
    await conn.nextJson();
    conn.send({
      'op': 'error',
      'error': 'Key in request is not valid',
      'code': 4,
      'reconnect': true,
      'requestId': null,
    });
    await expectLater(
      events.next,
      throwsA(isA<OtherParseError>().having((e) => e.code, 'code', 4)),
    );
    expect(await events.hasNext, isFalse);
    expect(await conn.messages.hasNext, isFalse);
  });

  test('close ends every live stream and the socket', () async {
    final c = await client(server);
    final events = started(c.collection(postSchema).query().live());
    final conn = await server.connections.next;
    await conn.accept();
    await conn.subscribed();
    expect(await events.next, isA<Subscribed<Post>>());
    c.close();
    expect(await events.hasNext, isFalse);
    expect(await conn.messages.hasNext, isFalse);
  });

  test('reconnects after 1 s doubling to 30 s, reset by connected', () async {
    final attempts = <Duration>[];
    final fake = FakeAsync();
    final refuse = server.connections.rest.listen((conn) {
      attempts.add(fake.elapsed);
      if (attempts.length == 8) {
        conn.send({'op': 'connected', 'clientId': 'c'});
      }
      // Lets the client read `connected` before the close.
      Timer(const Duration(milliseconds: 20), conn.socket.close);
    });
    addTearDown(refuse.cancel);

    Future<void> settle() async {
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
        fake
          ..flushMicrotasks()
          ..elapse(Duration.zero);
      }
    }

    late final ParseClient c;
    late final StreamSubscription<LiveEvent<Post>> sub;
    fake.run((_) {
      c = ParseClient(server: server.url, appId: 'app');
      sub = c.collection(postSchema).query().live().listen(null);
    });
    await settle();
    expect(attempts, [Duration.zero]);

    var expected = Duration.zero;
    for (final seconds in [1, 2, 4, 8, 16, 30, 30, 1]) {
      fake.elapse(Duration(seconds: seconds) - const Duration(milliseconds: 1));
      await settle();
      expect(attempts.last, expected, reason: 'retried before $seconds s');
      fake.elapse(const Duration(milliseconds: 1));
      await settle();
      expected += Duration(seconds: seconds);
      expect(attempts.last, expected);
    }
    expect(attempts, hasLength(9));

    fake.run((_) {
      sub.cancel();
      c.close();
    });
    await settle();
  });

  group('live() rejects', () {
    late Query<Post, PostFields, PostOps> query;
    setUp(() async {
      query = (await client(server)).collection(postSchema).query();
    });

    for (final (name, build) in [
      (
        'include',
        (Query<Post, PostFields, PostOps> q) => q.include((f) => f.author),
      ),
      (
        'orderBy',
        (Query<Post, PostFields, PostOps> q) => q.orderBy((f) => f.count.asc),
      ),
      ('limit', (Query<Post, PostFields, PostOps> q) => q.limit(1)),
      ('skip', (Query<Post, PostFields, PostOps> q) => q.skip(1)),
    ]) {
      test('$name with StateError', () {
        expect(() => build(query).live(), throwsStateError);
      });
    }

    final date = DateTime.utc(2024);
    for (final (name, Cond<Post> Function(PostFields) cond) in [
      ('fullText', (f) => f.title.fullText('word')),
      (
        'matchesQuery',
        (f) => f.author.matchesQuery(
          ParseClient(
            server: Uri.parse('http://h/parse'),
            appId: 'a',
          ).collection(authorSchema).query(),
        ),
      ),
      ('createdAt', (f) => f.createdAt.gt(date)),
      ('updatedAt', (f) => f.updatedAt.eq(date)),
      ('contains on a pointer list', (f) => f.coauthors.contains(Pointer('x'))),
      ('an empty containsAll', (f) => f.tags.containsAll([])),
      ('nested in |', (f) => f.title.eq('a') | f.title.fullText('word')),
    ]) {
      test('$name with ArgumentError', () {
        expect(() => query.where(cond).live(), throwsArgumentError);
      });
    }

    test('RelationField.of with ArgumentError', () async {
      final authors = (await client(server)).collection(authorSchema);
      expect(
        () => authors.where((_) => const PostFields().followers.of('p')).live(),
        throwsArgumentError,
      );
    });
  });

  test('ranges, regexes and polygons require the field to exist', () async {
    final c = await client(server);
    final date = DateTime.utc(2024);
    final sub = c
        .collection(postSchema)
        .where(
          (f) =>
              f.count.gt(1) &
              f.publishedAt.lte(date) &
              (f.title.startsWith('a') | f.slug.eq('s')),
        )
        .live()
        .listen(null);
    addTearDown(sub.cancel);
    final conn = await server.connections.next;
    await conn.accept();
    expect((await conn.nextJson())['query'], {
      'className': 'Post',
      'where': {
        'count': {r'$exists': true, r'$gt': 1},
        'publishedAt': {
          r'$exists': true,
          r'$lte': {'__type': 'Date', 'iso': '2024-01-01T00:00:00.000Z'},
        },
        r'$or': [
          {
            'title': {r'$exists': true, r'$regex': r'^\Qa\E'},
          },
          {'slug': 's'},
        ],
      },
    });
  });
}
