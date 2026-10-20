import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/note.dart';
import 'package:parse_next_it/models/post.dart';
import 'package:parse_next_it/models/user.dart';
import 'package:test/test.dart';

import 'support.dart';

const postSchema = $PostSchema();

/// Post has no `==`; comparing the encoded JSON makes a dropped or altered
/// field fail.
Matcher sameAs(Post p) => equals(postSchema.encode(p));
Map<String, Object?> wire(Post p) => postSchema.encode(p);

Post full(Pointer<User> a, Pointer<User> b) => Post(
      title: 'Hello, wörld 👋',
      subtitle: 'sub',
      likes: 3,
      views: 4,
      rating: 4.5,
      ratio: 2.0,
      score: 7,
      weight: 0.25,
      published: true,
      pinned: false,
      publishedAt: DateTime.utc(2024, 1, 2, 3, 4, 5, 678),
      editedAt: DateTime.utc(2024, 2, 3),
      status: PostStatus.published,
      previousStatus: PostStatus.draft,
      tags: const ['a', 'b'],
      ranks: const [1, 2, 3],
      meta: const {
        'n': 1,
        's': 'x',
        'nested': {'b': true},
        'list': [1, 'two'],
      },
      extra: const {'k': 'v'},
      author: a,
      editor: b,
      coauthors: [a, b],
      reviewers: [b],
      cover: const ParseFile(name: 'cover.png'),
      attachment: const ParseFile(name: 'notes.txt'),
      location: GeoPoint(27.7, 85.3),
      area: Polygon([GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(1, 1)]),
      zone: Polygon([GeoPoint(2, 2), GeoPoint(2, 3), GeoPoint(3, 3)]),
      thumbnail: Uint8List.fromList([0, 1, 2, 255]),
      data: Uint8List.fromList([9]),
    );

Post minimal(Pointer<User> a) => Post(
      title: 't',
      likes: 0,
      rating: 1,
      score: 1.5,
      published: false,
      publishedAt: DateTime.utc(2020),
      status: PostStatus.draft,
      tags: const [],
      meta: const {},
      author: a,
      coauthors: const [],
      cover: const ParseFile(name: 'c.png'),
      location: GeoPoint(-10, -20),
      area: Polygon([GeoPoint(5, 5), GeoPoint(5, 6), GeoPoint(6, 6)]),
      thumbnail: Uint8List.fromList([7]),
    );

void main() {
  forEachBackend((backend) {
    late ParseClient client;
    late Collection<Post, PostOps> posts;
    late Pointer<User> alice;
    late Pointer<User> bob;
    late String aliceToken;

    setUpAll(() async {
      Map<String, String> type(String t) => {'type': t};
      const user = {'type': 'Pointer', 'targetClass': '_User'};
      await backend.resetClass('Post', {
        for (final k in ['title', 'subtitle', 'status', 'previousStatus'])
          k: type('String'),
        for (final k in [
          'likes',
          'views',
          'rating',
          'ratio',
          'score',
          'weight'
        ])
          k: type('Number'),
        for (final k in ['published', 'pinned']) k: type('Boolean'),
        for (final k in ['published_at', 'editedAt']) k: type('Date'),
        for (final k in ['tags', 'ranks', 'coauthors', 'reviewers'])
          k: type('Array'),
        for (final k in ['meta', 'extra']) k: type('Object'),
        'author': user,
        'editor': user,
        'followers': {...user, 'type': 'Relation'},
        for (final k in ['cover', 'attachment']) k: type('File'),
        'location': type('GeoPoint'),
        for (final k in ['area', 'zone']) k: type('Polygon'),
        for (final k in ['thumb', 'data']) k: type('Bytes'),
      });
      await backend.resetClass('Note', {
        'text': type('String'),
        'draft': type('Boolean'),
        'place': type('GeoPoint'),
      });
      client = backend.client();
      posts = client.collection(postSchema);
      final a =
          await backend.signUp('alice', {'display_name': 'Alice', 'karma': 5});
      final b = await backend.signUp('bob');
      alice = Pointer(a.id);
      bob = Pointer(b.id);
      aliceToken = a.token;
    });

    tearDownAll(() => client.close());

    Future<Map<String, Object?>> raw(String id) =>
        backend.rest('GET', '/classes/Post/$id', master: true);

    Matcher sameItems(List<Object?> expected) =>
        // Postgres reorders arrays after AddUnique and Remove (see PLAN.md).
        backend.isPostgres ? unorderedEquals(expected) : equals(expected);

    group('round trip', () {
      for (final (name, build) in [
        ('every field set', () => full(alice, bob)),
        ('every nullable field null', () => minimal(alice)),
      ]) {
        test(name, () async {
          final x = build();
          final acl = Acl.publicRead().withPublic(write: true);
          final created = await posts.create(x, acl: acl);
          expect(wire(created.data), sameAs(x));
          expect(created.updatedAt, created.createdAt);
          expect(created.acl, acl);

          final got = await posts.get(created.id);
          expect(wire(got.data), sameAs(x));
          expect(got.id, created.id);
          expect(got.createdAt, created.createdAt);
          expect(got.updatedAt, created.updatedAt);
          expect(got.acl, acl);
        });
      }

      test('the Doc from create shows what a beforeSave trigger changed',
          () async {
        final notes = client.collection(const $NoteSchema());
        final created = await notes
            .create(Note(text: 'quiet', draft: true, place: GeoPoint(1, 2)));
        expect(created.data.text, 'QUIET');
        expect(created.data.draft, isNull);
        expect(created.data.place, GeoPoint(1, 2));

        final got = await notes.get(created.id);
        expect(got.data.text, 'QUIET');
        expect(got.data.draft, isNull);
        expect(got.data.place, GeoPoint(1, 2));
      });

      test('_User custom fields and renamed keys decode', () async {
        final users = client.collection(const $UserSchema());
        final got = await users.get(alice.id);
        expect(got.data.username, startsWith('alice-'));
        expect(got.data.displayName, 'Alice');
        expect(got.data.karma, 5);
      });
    });

    group('ops', () {
      test('20 increments from 20 clients in parallel', () async {
        final id = (await posts.create(minimal(alice))).id;
        final clients = [for (var i = 0; i < 20; i++) backend.client()];
        try {
          await Future.wait([
            for (final c in clients)
              c
                  .collection(postSchema)
                  .update(id, (o) => [o.likes.increment(1)]),
          ]);
        } finally {
          for (final c in clients) {
            c.close();
          }
        }
        expect((await posts.get(id)).data.likes, 20);
      });

      test('add, addUnique twice, remove', () async {
        final id = (await posts.create(full(alice, bob))).id;
        await posts.update(
            id,
            (o) => [
                  o.tags.add(['c'])
                ]);
        expect((await posts.get(id)).data.tags, ['a', 'b', 'c']);

        for (var i = 0; i < 2; i++) {
          await posts.update(
              id,
              (o) => [
                    o.tags.addUnique(['a', 'd'])
                  ]);
          expect(
              (await posts.get(id)).data.tags, sameItems(['a', 'b', 'c', 'd']));
        }

        await posts.update(
            id,
            (o) => [
                  o.tags.remove(['a', 'c']),
                  o.coauthors.remove([alice]),
                  o.ranks.addUnique([3, 4]),
                ]);
        final got = (await posts.get(id)).data;
        expect(got.tags, sameItems(['b', 'd']));
        expect([for (final p in got.coauthors) p.id], [bob.id]);
        expect(got.ranks, sameItems([1, 2, 3, 4]));
      });

      test('unset makes every nullable field absent', () async {
        final id = (await posts.create(full(alice, bob))).id;
        await posts.update(
            id,
            (o) => [
                  o.subtitle.unset(),
                  o.views.unset(),
                  o.ratio.unset(),
                  o.weight.unset(),
                  o.pinned.unset(),
                  o.editedAt.unset(),
                  o.previousStatus.unset(),
                  o.ranks.unset(),
                  o.extra.unset(),
                  o.editor.unset(),
                  o.reviewers.unset(),
                  o.attachment.unset(),
                  o.zone.unset(),
                  o.data.unset(),
                ]);
        final stored = await raw(id);
        for (final key in nullableKeys) {
          expect(stored, isNot(contains(key)), reason: key);
        }
        expect(wire((await posts.get(id)).data),
            sameAs(minimalOf(full(alice, bob))));
        await posts.delete(id);
      });

      test('set works for every wire type', () async {
        final id = (await posts.create(minimal(alice))).id;
        final x = full(bob, alice);
        await posts.update(
            id,
            (o) => [
                  o.title.set(x.title),
                  o.subtitle.set(x.subtitle!),
                  o.likes.set(x.likes),
                  o.views.set(x.views!),
                  o.rating.set(x.rating),
                  o.ratio.set(x.ratio!),
                  o.score.set(x.score),
                  o.weight.set(x.weight!),
                  o.published.set(x.published),
                  o.pinned.set(x.pinned!),
                  o.publishedAt.set(x.publishedAt),
                  o.editedAt.set(x.editedAt!),
                  o.status.set(x.status),
                  o.previousStatus.set(x.previousStatus!),
                  o.tags.set(x.tags),
                  o.ranks.set(x.ranks!),
                  o.meta.set(x.meta),
                  o.extra.set(x.extra!),
                  o.author.set(x.author),
                  o.editor.set(x.editor!),
                  o.coauthors.set(x.coauthors),
                  o.reviewers.set(x.reviewers!),
                  o.cover.set(x.cover),
                  o.attachment.set(x.attachment!),
                  o.location.set(x.location),
                  o.area.set(x.area),
                  o.zone.set(x.zone!),
                ]);
        expect(
          wire((await posts.get(id)).data),
          {...wire(x), 'thumb': wire(minimal(alice))['thumb'], 'data': null},
        );
      });

      test('set Bytes', skip: backend.isPostgres ? noBytesUpdate : null,
          () async {
        final id = (await posts.create(minimal(alice))).id;
        final x = full(alice, bob);
        await posts.update(
            id, (o) => [o.thumbnail.set(x.thumbnail), o.data.set(x.data!)]);
        final got = (await posts.get(id)).data;
        expect(got.thumbnail, x.thumbnail);
        expect(got.data, x.data);
      });

      test('relation add and remove', () async {
        final id = (await posts.create(minimal(alice))).id;
        await posts.update(
            id,
            (o) => [
                  o.followers.add([alice, bob])
                ]);
        expect(await backend.relatedIds('Post', id, 'followers', '_User'),
            unorderedEquals([alice.id, bob.id]));

        await posts.update(
            id,
            (o) => [
                  o.followers.remove([bob])
                ]);
        expect(await backend.relatedIds('Post', id, 'followers', '_User'),
            [alice.id]);
      });

      test('update returns the new updatedAt', () async {
        final created = await posts.create(minimal(alice));
        final updatedAt =
            await posts.update(created.id, (o) => [o.likes.increment(1)]);
        expect(updatedAt.isAfter(created.createdAt), isTrue);
        expect((await posts.get(created.id)).updatedAt, updatedAt);
      });
    });

    test('replace overwrites every field and keeps relations',
        skip: backend.isPostgres ? noBytesUpdate : null, () async {
      final id = (await posts.create(full(alice, bob))).id;
      await posts.update(
          id,
          (o) => [
                o.followers.add([bob])
              ]);
      final x = minimal(bob);
      final updatedAt = await posts.replace(id, x);

      final got = await posts.get(id);
      expect(wire(got.data), sameAs(x));
      expect(got.updatedAt, updatedAt);
      final stored = await raw(id);
      for (final key in nullableKeys) {
        expect(stored, isNot(contains(key)), reason: key);
      }
      expect(
          await backend.relatedIds('Post', id, 'followers', '_User'), [bob.id]);
    });

    test('replace sends null fields as Delete', () async {
      final notes = client.collection(const $NoteSchema());
      final id =
          (await notes.create(Note(text: 'a', place: GeoPoint(1, 2)))).id;
      await notes.replace(id, const Note(text: 'b'));
      final stored = await backend.rest('GET', '/classes/Note/$id');
      expect(stored, isNot(contains('place')));
      // The beforeSave trigger in cloud/main.js uppercases text.
      expect(stored['text'], 'B');
    });

    test('delete removes the object', () async {
      final id = (await posts.create(minimal(alice))).id;
      await posts.delete(id);
      await expectLater(posts.get(id), throwsA(isA<ObjectNotFound>()));
    });

    group('errors', () {
      test('a missing id is ObjectNotFound from get, update and delete',
          () async {
        await expectLater(
            posts.get('doesNotExist'), throwsA(isA<ObjectNotFound>()));
        await expectLater(
            posts.update('doesNotExist', (o) => [o.likes.increment(1)]),
            throwsA(isA<ObjectNotFound>()));
        await expectLater(
            posts.delete('doesNotExist'), throwsA(isA<ObjectNotFound>()));
      });

      test('an update the ACL denies is ObjectNotFound (101), not 403',
          () async {
        final r = await backend
            .rest('POST', '/classes/Post', token: aliceToken, body: {
          ...wire(minimal(alice))..removeWhere((_, v) => v == null),
          'ACL': {
            alice.id: {'read': true, 'write': true},
          },
        });
        final id = r['objectId']! as String;
        await expectLater(
          posts.update(id, (o) => [o.title.set('mine')]),
          throwsA(isA<ObjectNotFound>()
              .having((e) => e.code, 'code', 101)
              .having((e) => e.status, 'status', 404)),
        );
        final stored = await raw(id);
        expect(stored['title'], 't');
      });

      test('a wrong app id is Unauthorized', () async {
        final wrong = backend.client(appId: 'wrong-app-id');
        addTearDown(wrong.close);
        await expectLater(wrong.collection(postSchema).get('x'),
            throwsA(isA<Unauthorized>()));
      });

      test('an unreachable host is NetworkError', () async {
        final unreachable = ParseClient(
            server: Uri.parse('http://127.0.0.1:9/parse'), appId: 'x');
        addTearDown(unreachable.close);
        await expectLater(unreachable.collection(postSchema).get('x'),
            throwsA(isA<NetworkError>()));
      });
    });
  });
}

const noBytesUpdate = 'Postgres rejects any update that writes a Bytes value '
    "(119 \"Postgres doesn't support update\", updateObjectsByQuery in "
    'PostgresStorageAdapter.js), and Post has a required Bytes field';

const nullableKeys = [
  'subtitle',
  'views',
  'ratio',
  'weight',
  'pinned',
  'editedAt',
  'previousStatus',
  'ranks',
  'extra',
  'editor',
  'reviewers',
  'attachment',
  'zone',
  'data',
];

Post minimalOf(Post p) => Post(
      title: p.title,
      likes: p.likes,
      rating: p.rating,
      score: p.score,
      published: p.published,
      publishedAt: p.publishedAt,
      status: p.status,
      tags: p.tags,
      meta: p.meta,
      author: p.author,
      coauthors: p.coauthors,
      cover: p.cover,
      location: p.location,
      area: p.area,
      thumbnail: p.thumbnail,
    );
