// Restarts the servers, so it runs after, not beside, the other files.
@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/signal.dart';
import 'package:parse_next_it/models/user.dart';
import 'package:test/test.dart';

import 'live_support.dart';
import 'support.dart';

void main() {
  forEachBackend((backend) {
    setUpAll(() => resetSignals(backend));

    ParseClient client([SessionStore? sessions]) {
      final c = backend.client(sessions: sessions);
      addTearDown(c.close);
      return c;
    }

    Future<int> liveClients() async =>
        (await backend.rest(
              'POST',
              '/functions/liveClients',
              body: {},
            ))['result']!
            as int;

    test('each event type arrives once, in order', () async {
      final c = client().collection(signals);
      final name = unique('events');
      final watch = Watch(
        c.where((f) => f.name.eq(name) & f.points.gt(10)).live(),
      );
      await watch.confirmed();

      final doc = await c.create(Signal(name: name, points: 20));
      await c.update(doc.id, (o) => [o.points.set(30)]);
      await c.update(doc.id, (o) => [o.points.set(5)]);
      await c.update(doc.id, (o) => [o.points.set(15)]);
      await c.delete(doc.id);

      await until(() => watch.about(doc.id).length >= 5, reason: '5 events');
      await Future<void>.delayed(const Duration(seconds: 1));
      final events = watch.about(doc.id);
      expect(events, [
        isA<Created<Signal>>().having((e) => e.doc.data.points, 'points', 20),
        isA<Updated<Signal>>().having((e) => e.doc.data.points, 'points', 30),
        isA<Left<Signal>>().having((e) => e.doc.data.points, 'points', 5),
        isA<Entered<Signal>>().having((e) => e.doc.data.points, 'points', 15),
        isA<Deleted<Signal>>().having((e) => e.doc.data.points, 'points', 15),
      ]);
      expect(watch.errors, isEmpty);
    });

    test(
      'a restarted server is resubscribed and delivers later writes',
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        final c = client().collection(signals);
        final name = unique('restart');
        final watch = Watch(c.where((f) => f.name.eq(name)).live());
        await watch.confirmed();

        final restart = await Process.run('docker', [
          'compose',
          '-f',
          '../../docker/compose.yaml',
          'restart',
          'parse-${backend.name}',
        ]);
        expect(restart.exitCode, 0, reason: '${restart.stderr}');

        await watch.confirmed(2);
        expect(watch.subscribed, 2);
        expect(
          watch.events.whereType<Disconnected<Signal>>(),
          hasLength(1),
          reason: 'one Disconnected between the two Subscribed',
        );
        expect(
          watch.events.indexWhere((e) => e is Disconnected),
          lessThan(watch.events.lastIndexWhere((e) => e is Subscribed)),
        );
        final after = await c.create(Signal(name: name));
        await until(() => watch.about(after.id).isNotEmpty, reason: 'event');
        expect(watch.about(after.id).single, isA<Created<Signal>>());
        expect(watch.errors, isEmpty);
        expect(watch.done, isFalse);
      },
    );

    test('a File field reaches create and update events', () async {
      final c = client();
      await c
          .auth(const $UserSchema())
          .become((await backend.signUp('up')).token);
      final file = await c.uploadFile(
        Uint8List.fromList([1, 2, 3]),
        name: 'live.png',
        contentType: 'image/png',
      );
      final signalsOf = c.collection(signals);
      final name = unique('file');
      final watch = Watch(signalsOf.where((f) => f.name.eq(name)).live());
      await watch.confirmed();

      final doc = await signalsOf.create(Signal(name: name, file: file));
      await signalsOf.update(doc.id, (o) => [o.points.set(1)]);

      await until(() => watch.about(doc.id).length >= 2, reason: '2 events');
      for (final e in watch.about(doc.id).cast<Object>()) {
        final got = switch (e) {
          Created(:final doc) || Updated(:final doc) => doc.data.file,
          _ => null,
        };
        expect(got, file);
        expect(got?.url, file.url);
      }
      expect(watch.errors, isEmpty);
    });

    test('watch reports an update only when a watched field changed', () async {
      final c = client().collection(signals);
      final name = unique('watch');
      final watch = Watch(
        c.where((f) => f.name.eq(name)).live(watch: (f) => [f.points]),
      );
      await watch.confirmed();

      final doc = await c.create(Signal(name: name, points: 1));
      await c.update(doc.id, (o) => [o.label.set('quiet')]);
      await c.update(doc.id, (o) => [o.points.set(2)]);
      await until(() => watch.about(doc.id).length >= 2, reason: '2 events');
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(watch.about(doc.id), [
        isA<Created<Signal>>(),
        isA<Updated<Signal>>().having((e) => e.doc.data.points, 'points', 2),
      ]);
    });

    test('after cancel nothing arrives and the socket closes', () async {
      var now = await liveClients();
      for (var i = 0; i < 200 && now != 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        now = await liveClients();
      }
      expect(now, 0, reason: 'sockets left open by earlier tests');
      final c = client().collection(signals);
      final name = unique('cancel');
      final watch = Watch(c.where((f) => f.name.eq(name)).live());
      await watch.confirmed();
      expect(await liveClients(), 1);

      await watch.cancel();
      final count = watch.events.length;
      await c.create(Signal(name: name));
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(watch.events, hasLength(count));

      now = await liveClients();
      for (var i = 0; i < 200 && now != 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        now = await liveClients();
      }
      expect(now, 0);
    });

    test('an ACL-protected object reaches only its reader', () async {
      final alice = await backend.signUp('alice');
      final bob = await backend.signUp('bob');
      final a = client();
      final b = client();
      await a.auth(const $UserSchema()).become(alice.token);
      await b.auth(const $UserSchema()).become(bob.token);
      final name = unique('acl');
      final aliceWatch = Watch(
        a.collection(signals).where((f) => f.name.eq(name)).live(),
      );
      final bobWatch = Watch(
        b.collection(signals).where((f) => f.name.eq(name)).live(),
      );
      final writer = a.collection(signals);
      await aliceWatch.confirmed();
      await bobWatch.confirmed();

      final private = await writer.create(
        Signal(name: name),
        acl: const Acl().withUser(alice.id, write: true),
      );
      final public = await writer.create(Signal(name: name));
      await until(
        () =>
            aliceWatch.about(public.id).isNotEmpty &&
            bobWatch.about(public.id).isNotEmpty,
        reason: 'public object seen by both',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(aliceWatch.about(private.id).single, isA<Created<Signal>>());
      expect(bobWatch.about(private.id), isEmpty);
    });

    test(
      'a subscription made after logout sees none of the old session',
      () async {
        final a = client();
        final auth = a.auth(const $UserSchema());
        final name = unique('logout');
        final alice = await auth.signUp(
          password: 'pw',
          user: User(username: name),
        );
        final signals_ = a.collection(signals);
        final aliceWatch = Watch(signals_.where((f) => f.name.eq(name)).live());
        await aliceWatch.confirmed();

        // A second session, so the logout revokes only that one and the first
        // subscription's token stays valid.
        await auth.logIn(name, 'pw');
        await auth.logOut();
        final anonWatch = Watch(signals_.where((f) => f.name.eq(name)).live());
        await anonWatch.confirmed();

        final private = await backend.rest(
          'POST',
          '/classes/Signal',
          master: true,
          body: {
            'name': name,
            'ACL': {
              alice.id: {'read': true, 'write': true},
            },
          },
        );
        final public = await backend.rest(
          'POST',
          '/classes/Signal',
          body: {'name': name},
        );
        final privateId = private['objectId']! as String;
        final publicId = public['objectId']! as String;
        await until(
          () =>
              aliceWatch.about(publicId).isNotEmpty &&
              anonWatch.about(publicId).isNotEmpty,
          reason: 'public object seen by both',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(aliceWatch.about(privateId).single, isA<Created<Signal>>());
        expect(anonWatch.about(privateId), isEmpty);
      },
    );

    test('a subscription the server rejects ends with its error', () async {
      final c = client().collection(signals);
      final watch = Watch(c.where((f) => f.label.matches('(')).live());
      await until(() => watch.done, reason: 'stream done');
      expect(watch.errors, [
        isA<OtherParseError>()
            .having((e) => e.code, 'code', 102)
            .having((e) => e.status, 'status', 400),
      ]);
      expect(watch.events, isEmpty);
    });
  });
}
