import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/user.dart';
import 'package:test/test.dart';

import 'support.dart';

const users = $UserSchema();

/// Passes requests to a real client and keeps their headers.
final class Recording extends http.BaseClient {
  final _inner = http.Client();
  final headers = <Map<String, String>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    headers.add({...request.headers});
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

String unique(String name) => '$name-${DateTime.now().microsecondsSinceEpoch}';

Future<String> storedToken(SessionStore store) async =>
    (jsonDecode((await store.read())!) as Map<String, Object?>)['sessionToken']!
        as String;

void main() {
  forEachBackend((backend) {
    ParseClient client([SessionStore? sessions]) {
      final c = backend.client(sessions: sessions);
      addTearDown(c.close);
      return c;
    }

    Future<List<String>> sentMail() async {
      final r = await backend.rest('POST', '/functions/sentMail', body: {});
      return [for (final to in r['result']! as List<Object?>) to! as String];
    }

    test('sign up, current, log out, log in, me, become', () async {
      final store = InMemorySessionStore();
      final auth = client(store).auth(users);
      final events = <Doc<User>?>[];
      final sub = auth.changes.listen(events.add);
      addTearDown(sub.cancel);
      final name = unique('life');

      final signedUp = await auth.signUp(
        password: 'pw',
        user: User(username: name, karma: 3),
      );
      expect(signedUp.data.username, name);
      expect(signedUp.data.karma, 3);
      expect(signedUp.updatedAt, signedUp.createdAt);
      expect((await auth.current())!.id, signedUp.id);
      expect(await store.read(), isNot(contains('"password"')));

      await auth.logOut();
      expect(await auth.current(), isNull);
      expect(await store.read(), isNull);

      final loggedIn = await auth.logIn(name, 'pw');
      expect(loggedIn.id, signedUp.id);
      expect(loggedIn.acl!.user(signedUp.id), (read: true, write: true));
      final token = await storedToken(store);

      final me = await auth.me();
      expect(me.id, signedUp.id);
      expect(me.data.karma, 3);

      final other = client().auth(users);
      final became = await other.become(token);
      expect(became.id, signedUp.id);
      expect((await other.current())!.data.username, name);

      await pumpEventQueue();
      expect([for (final e in events) e?.id], [signedUp.id, null, signedUp.id]);
    });

    test('the session token never reaches the stored user', () async {
      final store = InMemorySessionStore();
      final auth = client(store).auth(users);
      await auth.signUp(
        password: 'pw',
        user: User(username: unique('tok')),
      );
      await auth.me();
      final stored = jsonDecode((await store.read())!) as Map<String, Object?>;
      expect(stored.keys, unorderedEquals(['sessionToken', 'user']));
      expect(stored['user'], isNot(contains('sessionToken')));
    });

    test('a wrong password is InvalidCredentials', () async {
      final auth = client().auth(users);
      final name = unique('wrong');
      await auth.signUp(
        password: 'pw',
        user: User(username: name),
      );
      await expectLater(
        client().auth(users).logIn(name, 'nope'),
        throwsA(
          isA<InvalidCredentials>()
              .having((e) => e.code, 'code', 101)
              .having((e) => e.status, 'status', 404),
        ),
      );
    });

    test('a taken username is UsernameTaken', () async {
      final name = unique('taken');
      await client()
          .auth(users)
          .signUp(
            password: 'pw',
            user: User(username: name),
          );
      await expectLater(
        client()
            .auth(users)
            .signUp(
              password: 'pw',
              user: User(username: name),
            ),
        throwsA(isA<UsernameTaken>().having((e) => e.code, 'code', 202)),
      );
    });

    test('a taken email is EmailTaken', () async {
      final email = '${unique('mail')}@example.test';
      await client()
          .auth(users)
          .signUp(
            password: 'pw',
            user: User(username: unique('a'), email: email),
          );
      await expectLater(
        client()
            .auth(users)
            .signUp(
              password: 'pw',
              user: User(username: unique('b'), email: email),
            ),
        throwsA(isA<EmailTaken>().having((e) => e.code, 'code', 203)),
      );
    });

    test('a second client on the same store is logged in', () async {
      final store = InMemorySessionStore();
      final first = await client(store)
          .auth(users)
          .signUp(
            password: 'pw',
            user: User(username: unique('shared')),
          );

      final recording = Recording();
      final second = backend.client(sessions: store, httpClient: recording);
      addTearDown(() {
        second.close();
        recording.close();
      });
      expect((await second.auth(users).current())!.id, first.id);
      expect(recording.headers, isEmpty);

      // enforcePrivateUsers: only the user's own session can read it.
      final got = await second.collection(users).get(first.id);
      expect(got.id, first.id);
      expect(
        recording.headers.single['X-Parse-Session-Token'],
        await storedToken(store),
      );
    });

    test('a session revoked elsewhere is cleared on the next call', () async {
      final storeA = InMemorySessionStore();
      final a = client(storeA);
      final name = unique('revoked');
      final user = await a
          .auth(users)
          .signUp(
            password: 'pw',
            user: User(username: name),
          );
      final events = <Doc<User>?>[];
      final sub = a.auth(users).changes.listen(events.add);
      addTearDown(sub.cancel);

      final b = client(InMemorySessionStore()).auth(users);
      await b.logIn(name, 'pw');
      final sessions = await backend.rest(
        'GET',
        '/classes/_Session',
        master: true,
        query: {
          'where': jsonEncode({'sessionToken': await storedToken(storeA)}),
        },
      );
      final sessionId =
          ((sessions['results']! as List<Object?>).single!
                  as Map<String, Object?>)['objectId']!
              as String;
      await backend.rest(
        'DELETE',
        '/classes/_Session/$sessionId',
        master: true,
      );

      await expectLater(
        a.collection(users).get(user.id),
        throwsA(isA<InvalidSession>()),
      );
      expect(await a.auth(users).current(), isNull);
      expect(await storeA.read(), isNull);
      await expectLater(
        a.collection(users).get(user.id),
        throwsA(isA<ObjectNotFound>()),
      );
      await pumpEventQueue();
      expect(events, [null]);
      expect((await b.me()).id, user.id);
    });

    test('logOut with the server unreachable still logs out locally', () async {
      final store = InMemorySessionStore();
      await client(store)
          .auth(users)
          .signUp(
            password: 'pw',
            user: User(username: unique('offline')),
          );

      final offline = ParseClient(
        server: Uri.parse('http://127.0.0.1:9/parse'),
        appId: 'x',
        sessions: store,
      );
      addTearDown(offline.close);
      final auth = offline.auth(users);
      await expectLater(auth.logOut(), throwsA(isA<NetworkError>()));
      expect(await auth.current(), isNull);
      expect(await store.read(), isNull);
    });

    group('requestPasswordReset', () {
      test('mails a known address', () async {
        final email = '${unique('reset')}@example.test';
        await client()
            .auth(users)
            .signUp(
              password: 'pw',
              user: User(username: unique('reset'), email: email),
            );
        await client().auth(users).requestPasswordReset(email);
        expect(await sentMail(), contains(email));
      });

      test('succeeds for an unknown address and mails nothing', () async {
        final email = '${unique('nobody')}@example.test';
        await client().auth(users).requestPasswordReset(email);
        expect(await sentMail(), isNot(contains(email)));
      });
    });
  });
}
