import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parse_next/parse_next.dart';
import 'package:test/test.dart';

import 'models.dart';

const at = '2024-01-02T03:04:05.678Z';
const ann = {
  'objectId': 'u1',
  'createdAt': at,
  'updatedAt': at,
  'username': 'ann',
};

String session(String token, [Map<String, Object?> user = ann]) =>
    jsonEncode({'sessionToken': token, 'user': user});

final class Store implements SessionStore {
  Store([this.value]);

  String? value;
  var reads = 0;
  var writes = 0;
  var clears = 0;
  Object? failNextRead;

  @override
  Future<String?> read() async {
    reads++;
    await Future<void>.delayed(Duration.zero);
    if (failNextRead case final e?) {
      failNextRead = null;
      throw e;
    }
    return value;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    this.value = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

/// Answers each request with [respond] and records it.
final class Server {
  Server(this.respond, {Store? store}) : store = store ?? Store();

  final http.Response Function(http.Request r) respond;
  final Store store;
  final requests = <http.Request>[];

  late final client = ParseClient(
    server: Uri.parse('http://parse.test/parse'),
    appId: 'app',
    sessions: store,
    httpClient: MockClient((r) async {
      requests.add(r);
      return respond(r);
    }),
  );
  late final auth = client.auth(memberSchema);
  late final members = client.collection(memberSchema);

  List<String?> get tokens => [
    for (final r in requests) r.headers['X-Parse-Session-Token'],
  ];
}

http.Response ok([Map<String, Object?> body = const {}]) =>
    http.Response(jsonEncode(body), 200);

http.Response error(int code, int status) =>
    http.Response(jsonEncode({'code': code, 'error': 'e$code'}), status);

http.Response userWith(String token) => ok({...ann, 'sessionToken': token});

void main() {
  group('sends exactly', () {
    void expectOnly(
      Server s,
      String method,
      String path, {
      String? token,
      Object? body,
    }) {
      final r = s.requests.single;
      expect(r.method, method);
      expect(r.url.toString(), 'http://parse.test/parse$path');
      expect(r.headers, {
        'X-Parse-Application-Id': 'app',
        'X-Parse-Session-Token': ?token,
        if (body != null) 'Content-Type': 'application/json',
      });
      expect(r.body.isEmpty ? null : jsonDecode(r.body), body);
    }

    test('signUp, without the stored token or null fields', () async {
      final s = Server(
        (_) => ok({'objectId': 'u1', 'createdAt': at, 'sessionToken': 'r:n'}),
        store: Store(session('r:old')),
      );
      await s.auth.signUp(
        password: 'pw',
        user: const Member(username: 'ann'),
      );
      expectOnly(
        s,
        'POST',
        '/users',
        body: {'username': 'ann', 'password': 'pw'},
      );
    });

    test('logIn, without the stored token', () async {
      final s = Server((_) => userWith('r:n'), store: Store(session('r:old')));
      await s.auth.logIn('ann', 'pw');
      expectOnly(
        s,
        'POST',
        '/login',
        body: {'username': 'ann', 'password': 'pw'},
      );
    });

    test('become, with the given token', () async {
      final s = Server(
        (_) => userWith('r:new'),
        store: Store(session('r:old')),
      );
      await s.auth.become('r:new');
      expectOnly(s, 'GET', '/users/me', token: 'r:new');
      expect(s.store.value, session('r:new'));
    });

    test('me, with the stored token', () async {
      final s = Server((_) => userWith('r:t'), store: Store(session('r:t')));
      await s.auth.me();
      expectOnly(s, 'GET', '/users/me', token: 'r:t');
    });

    test('logOut, with the token it cleared', () async {
      final s = Server((_) => ok(), store: Store(session('r:t')));
      await s.auth.logOut();
      expectOnly(s, 'POST', '/logout', token: 'r:t');
    });

    test('logOut when logged out sends nothing', () async {
      final s = Server((_) => ok());
      await s.auth.logOut();
      expect(s.requests, isEmpty);
    });

    test('requestPasswordReset, without the stored token', () async {
      final s = Server((_) => ok(), store: Store(session('r:t')));
      await s.auth.requestPasswordReset('a@example.test');
      expectOnly(
        s,
        'POST',
        '/requestPasswordReset',
        body: {'email': 'a@example.test'},
      );
    });

    test('current, nothing', () async {
      final s = Server((_) => ok(), store: Store(session('r:t')));
      expect((await s.auth.current())!.data.username, 'ann');
      expect(s.requests, isEmpty);
    });
  });

  test('Collection and Query requests carry the stored token', () async {
    final s = Server(
      (r) => r.url.path.endsWith('/u1')
          ? ok(ann)
          : ok({
              'results': [ann],
            }),
      store: Store(session('r:t')),
    );
    await s.members.get('u1');
    await s.members.query().find();
    expect(s.tokens, ['r:t', 'r:t']);
  });

  test('the store is read once under concurrent first calls', () async {
    final s = Server(
      (r) => r.url.path.endsWith('/u1')
          ? ok(ann)
          : ok({
              'results': [ann],
            }),
      store: Store(session('r:t')),
    );
    await Future.wait([
      s.members.get('u1'),
      s.members.query().find(),
      s.auth.current(),
      s.members.get('u1'),
    ]);
    expect(s.store.reads, 1);
    expect(s.tokens, ['r:t', 'r:t', 'r:t']);
    await s.members.get('u1');
    expect(s.store.reads, 1);
  });

  test('a failed store read is thrown and retried on the next call', () async {
    final s = Server((_) => ok(ann), store: Store(session('r:t')))
      ..store.failNextRead = StateError('locked');
    await expectLater(s.members.get('u1'), throwsStateError);
    await s.members.get('u1');
    expect(s.store.reads, 2);
    expect(s.tokens, ['r:t']);
  });

  group('a corrupt stored value', () {
    for (final raw in ['not json', '[]', '{"user":{}}']) {
      test('$raw is a DecodeError until logOut', () async {
        final s = Server((_) => ok(ann), store: Store(raw));
        await expectLater(s.auth.current(), throwsA(isA<DecodeError>()));
        await expectLater(s.auth.logOut(), throwsA(isA<DecodeError>()));
        expect(s.store.value, isNull);
        expect(await s.auth.current(), isNull);
        expect(s.requests, isEmpty);
      });
    }
  });

  group('209', () {
    test('on the stored token clears it once and rethrows', () async {
      final s = Server((_) => error(209, 400), store: Store(session('r:t')));
      final events = <Doc<Member>?>[];
      s.auth.changes.listen(events.add);
      final results = await Future.wait([
        for (var i = 0; i < 3; i++)
          s.members.get('u1').then<Object?>((d) => d, onError: (Object e) => e),
      ]);
      expect(results, everyElement(isA<InvalidSession>()));
      expect(s.store.clears, 1);
      expect(s.store.value, isNull);
      expect(await s.auth.current(), isNull);
      await pumpEventQueue();
      expect(events, [null]);
    });

    test('from a Query clears the session', () async {
      final s = Server((_) => error(209, 400), store: Store(session('r:t')));
      await expectLater(
        s.members.query().count(),
        throwsA(isA<InvalidSession>()),
      );
      expect(await s.auth.current(), isNull);
    });

    test('the next request carries no token', () async {
      var calls = 0;
      final s = Server(
        (_) => calls++ == 0 ? error(209, 400) : ok(ann),
        store: Store(session('r:t')),
      );
      await expectLater(s.members.get('u1'), throwsA(isA<InvalidSession>()));
      await s.members.get('u1');
      expect(s.tokens, ['r:t', null]);
    });

    test('for a token given to become keeps the stored session', () async {
      final s = Server((_) => error(209, 400), store: Store(session('r:t')));
      await expectLater(s.auth.become('r:bad'), throwsA(isA<InvalidSession>()));
      expect(s.store.clears, 0);
      expect(s.store.value, session('r:t'));
    });

    test('from logOut is thrown after the local clear', () async {
      final s = Server((_) => error(209, 400), store: Store(session('r:t')));
      final events = <Doc<Member>?>[];
      s.auth.changes.listen(events.add);
      await expectLater(s.auth.logOut(), throwsA(isA<InvalidSession>()));
      expect(s.store.value, isNull);
      await pumpEventQueue();
      expect(events, [null]);
    });

    test('without a session clears nothing', () async {
      final s = Server((_) => error(209, 400));
      await expectLater(s.members.get('u1'), throwsA(isA<InvalidSession>()));
      expect(s.store.clears, 0);
    });
  });

  test('logOut clears the session even when the request fails', () async {
    final store = Store(session('r:t'));
    final client = ParseClient(
      server: Uri.parse('http://parse.test/parse'),
      appId: 'app',
      sessions: store,
      httpClient: MockClient((r) async {
        expect(store.value, isNull);
        throw http.ClientException('refused', r.url);
      }),
    );
    final auth = client.auth(memberSchema);
    await expectLater(auth.logOut(), throwsA(isA<NetworkError>()));
    expect(store.value, isNull);
    expect(await auth.current(), isNull);
  });

  group('101', () {
    test('from /login is InvalidCredentials', () async {
      final s = Server((_) => error(101, 404));
      await expectLater(
        s.auth.logIn('ann', 'bad'),
        throwsA(isA<InvalidCredentials>().having((e) => e.status, 's', 404)),
      );
    });

    test('from any other route is ObjectNotFound', () async {
      final s = Server((_) => error(101, 404), store: Store(session('r:t')));
      await expectLater(s.auth.me(), throwsA(isA<ObjectNotFound>()));
      await expectLater(s.members.get('u1'), throwsA(isA<ObjectNotFound>()));
      await expectLater(s.auth.become('r:t'), throwsA(isA<ObjectNotFound>()));
    });
  });

  group('stored session', () {
    test('is the token and the user without its token', () async {
      final s = Server((_) => userWith('r:t'));
      await s.auth.logIn('ann', 'pw');
      expect(jsonDecode(s.store.value!), {'sessionToken': 'r:t', 'user': ann});
    });

    test('sign-up stores what was sent with the response', () async {
      final s = Server(
        (_) => ok({'objectId': 'u1', 'createdAt': at, 'sessionToken': 'r:t'}),
      );
      final doc = await s.auth.signUp(
        password: 'pw',
        user: const Member(username: 'ann', email: 'a@example.test'),
      );
      expect(jsonDecode(s.store.value!), {
        'sessionToken': 'r:t',
        'user': {...ann, 'email': 'a@example.test'},
      });
      expect(doc.updatedAt, doc.createdAt);
      expect(doc.data.decodedKeys, isNot(contains('sessionToken')));
    });

    test('round-trips through a second client on the same store', () async {
      final store = Store();
      final first = Server((_) => userWith('r:t'), store: store);
      final loggedIn = await first.auth.logIn('ann', 'pw');

      final second = Server((_) => ok(ann), store: store);
      final current = (await second.auth.current())!;
      expect(current.id, loggedIn.id);
      expect(current.createdAt, loggedIn.createdAt);
      expect(current.updatedAt, loggedIn.updatedAt);
      expect(current.data.username, 'ann');
      expect(current.data.decodedKeys, loggedIn.data.decodedKeys);
      await second.members.get('u1');
      expect(second.tokens, ['r:t']);
    });

    test('me updates the stored user without emitting', () async {
      final s = Server(
        (_) => ok({...ann, 'username': 'anna', 'sessionToken': 'r:t'}),
        store: Store(session('r:t')),
      );
      final events = <Doc<Member>?>[];
      s.auth.changes.listen(events.add);
      await s.auth.me();
      expect((await s.auth.current())!.data.username, 'anna');
      expect(jsonDecode(s.store.value!), {
        'sessionToken': 'r:t',
        'user': {...ann, 'username': 'anna'},
      });
      await pumpEventQueue();
      expect(events, isEmpty);
    });

    test('me does not bring back a session logged out meanwhile', () async {
      final reply = Completer<http.Response>();
      final store = Store(session('r:t'));
      final client = ParseClient(
        server: Uri.parse('http://parse.test/parse'),
        appId: 'app',
        sessions: store,
        httpClient: MockClient(
          (r) => r.url.path.endsWith('/me') ? reply.future : Future.value(ok()),
        ),
      );
      final auth = client.auth(memberSchema);
      final me = auth.me();
      await pumpEventQueue();
      await auth.logOut();
      reply.complete(userWith('r:t'));
      await me;
      expect(store.value, isNull);
      expect(await auth.current(), isNull);
    });
  });

  test('changes emits on signUp, logIn, become and logOut', () async {
    final s = Server(
      (r) => switch (r.url.path) {
        '/parse/users' => ok({
          'objectId': 'u1',
          'createdAt': at,
          'sessionToken': 'r:1',
        }),
        '/parse/logout' => ok(),
        _ => userWith('r:2'),
      },
    );
    final events = <String?>[];
    s.auth.changes.listen((d) => events.add(d?.data.username));
    await s.auth.signUp(
      password: 'pw',
      user: const Member(username: 'ann'),
    );
    await s.auth.logOut();
    await s.auth.logIn('ann', 'pw');
    await s.auth.become('r:2');
    await pumpEventQueue();
    expect(events, ['ann', null, 'ann', 'ann']);
  });
}
