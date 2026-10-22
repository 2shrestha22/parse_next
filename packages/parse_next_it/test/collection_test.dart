import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/note.dart';
import 'package:parse_next_it/models/post.dart';
import 'package:parse_next_it/models/signal.dart';
import 'package:parse_next_it/models/user.dart';
import 'package:test/test.dart';

import 'live_support.dart' show resetSignals, signals;
import 'support.dart';

const postSchema = $PostSchema();

/// Post has no `==`; comparing the encoded JSON makes a dropped or altered
/// field fail. File URLs are left out: the server builds them, so a file sent
/// without one comes back with one.
Matcher sameAs(Post p) => equals(wire(p));
Map<String, Object?> noteWire(Note n) => const $NoteSchema().encode(n);

Map<String, Object?> wire(Post p) => {
  for (final MapEntry(:key, :value) in postSchema.encode(p).entries)
    key: switch (value) {
      {'__type': 'File', 'name': final name} => {
        '__type': 'File',
        'name': name,
      },
      _ => value,
    },
};

/// A file as the server returns one. Its URL is never checked, and the server
/// keeps only the name.
ParseFile file(String name) =>
    ParseFile(name: name, url: 'http://files.test/$name');

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
  cover: file('cover.png'),
  attachment: file('notes.txt'),
  location: GeoPoint(27.7, 85.3),
  area: Polygon([GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(1, 1)]),
  zone: Polygon([GeoPoint(2, 2), GeoPoint(2, 3), GeoPoint(3, 3)]),
  thumbnail: Uint8List.fromList([0, 1, 2, 255]),
  data: Uint8List.fromList([9]),
  buckets: [
    {'date': '2026-10-20', 'count': 4},
    {
      'at': DateTime.utc(2026, 10, 21),
      'nested': {'file': file('n.txt')},
    },
  ],
  dates: [DateTime.utc(2024, 1, 2, 3, 4, 5, 678), DateTime.utc(2020)],
  spots: [GeoPoint(1, 2), GeoPoint(-3, 4)],
  files: [file('a.txt'), file('b.txt')],
);

Post minimal(
  Pointer<User> a, {
  ParseFile? cover,
  int likes = 0,
  List<String> tags = const [],
  List<int>? ranks,
  Map<String, Object?> meta = const {},
  Polygon? area,
}) => Post(
  title: 't',
  likes: likes,
  rating: 1,
  score: 1.5,
  published: false,
  publishedAt: DateTime.utc(2020),
  status: PostStatus.draft,
  tags: tags,
  ranks: ranks,
  meta: meta,
  author: a,
  coauthors: const [],
  cover: cover ?? file('c.png'),
  location: GeoPoint(-10, -20),
  area: area ?? Polygon([GeoPoint(5, 5), GeoPoint(5, 6), GeoPoint(6, 6)]),
  thumbnail: Uint8List.fromList([7]),
);

void main() {
  forEachBackend((backend) {
    late ParseClient client;
    late Collection<Post, PostFields, PostOps> posts;
    late Pointer<User> alice;
    late Pointer<User> bob;
    late String aliceToken;
    late String bobToken;

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
          'weight',
        ])
          k: type('Number'),
        for (final k in ['published', 'pinned']) k: type('Boolean'),
        for (final k in ['published_at', 'editedAt']) k: type('Date'),
        for (final k in [
          'tags',
          'ranks',
          'coauthors',
          'reviewers',
          'buckets',
          'dates',
          'spots',
          'files',
        ])
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
        'attachment': type('File'),
      });
      client = backend.client();
      posts = client.collection(postSchema);
      final a = await backend.signUp('alice', {
        'display_name': 'Alice',
        'karma': 5,
      });
      final b = await backend.signUp('bob');
      alice = Pointer(a.id);
      bob = Pointer(b.id);
      aliceToken = a.token;
      bobToken = b.token;
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
          final acl = const Acl().withPublic().withPublic(write: true);
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

      test(
        'the Doc from create shows what a beforeSave trigger changed',
        () async {
          final notes = client.collection(const $NoteSchema());
          final created = await notes.create(
            Note(text: 'quiet', draft: true, place: GeoPoint(1, 2)),
          );
          expect(created.data.text, 'QUIET');
          expect(created.data.draft, isNull);
          expect(created.data.place, GeoPoint(1, 2));

          final got = await notes.get(created.id);
          expect(got.data.text, 'QUIET');
          expect(got.data.draft, isNull);
          expect(got.data.place, GeoPoint(1, 2));
        },
      );

      test('_User custom fields and renamed keys decode', () async {
        final users = client.collection(const $UserSchema());
        final got = await users.get(alice.id);
        expect(got.data.username, startsWith('alice-'));
        expect(got.data.displayName, 'Alice');
        expect(got.data.karma, 5);
      });
    });

    group('ops', () {
      test('add, addUnique twice, remove', () async {
        final id = (await posts.create(full(alice, bob))).id;
        await posts.update(
          id,
          (o) => [
            o.tags.add(['c']),
          ],
        );
        expect((await posts.get(id)).data.tags, ['a', 'b', 'c']);

        for (var i = 0; i < 2; i++) {
          await posts.update(
            id,
            (o) => [
              o.tags.addUnique(['a', 'd']),
            ],
          );
          expect(
            (await posts.get(id)).data.tags,
            sameItems(['a', 'b', 'c', 'd']),
          );
        }

        await posts.update(
          id,
          (o) => [
            o.tags.remove(['a', 'c']),
            o.coauthors.remove([alice]),
            o.ranks.addUnique([3, 4]),
          ],
        );
        final got = (await posts.get(id)).data;
        expect(got.tags, sameItems(['b', 'd']));
        expect([for (final p in got.coauthors) p.id], [bob.id]);
        expect(got.ranks, sameItems([1, 2, 3, 4]));
      });

      test('lists of maps, dates, GeoPoints and files', () async {
        final x = full(alice, bob);
        final id = (await posts.create(x)).id;
        final bucket = {'date': '2026-10-22', 'count': 1};
        final day = DateTime.utc(2025);
        await posts.update(
          id,
          (o) => [
            o.buckets.addUnique([bucket, x.buckets.first]),
            o.dates.add([day]),
            o.spots.remove([GeoPoint(1, 2)]),
            o.files.remove([file('a.txt')]),
          ],
        );
        final got = (await posts.get(id)).data;
        expect(got.buckets, sameItems([...x.buckets, bucket]));
        expect(got.dates, [...x.dates!, day]);
        expect(got.spots, [GeoPoint(-3, 4)]);
        expect(got.files, [file('b.txt')]);

        Future<bool> finds(Cond<Post> Function(PostFields f) c) async =>
            await posts.where((f) => f.id.eq(id) & c(f)).count() == 1;
        expect(await finds((f) => f.buckets.contains(bucket)), isTrue);
        expect(
          await finds((f) => f.buckets.contains({...bucket, 'count': 2})),
          isFalse,
        );
        expect(await finds((f) => f.dates.contains(day)), isTrue);
        expect(
          await finds((f) => f.dates.containsAny([DateTime.utc(2019)])),
          isFalse,
        );
        expect(await finds((f) => f.spots.contains(GeoPoint(-3, 4))), isTrue);
        expect(await finds((f) => f.files.contains(file('b.txt'))), isTrue);

        // The quirks the README lists: a file in a list matches by URL too,
        // and on Mongo a map matches only with its keys in the same order.
        expect(
          await finds(
            (f) => f.files.contains(
              const ParseFile(name: 'b.txt', url: 'http://elsewhere/b.txt'),
            ),
          ),
          isFalse,
        );
        expect(
          await finds(
            (f) => f.buckets.contains({'count': 1, 'date': '2026-10-22'}),
          ),
          backend.isPostgres,
        );
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
            o.dates.unset(),
            o.spots.unset(),
            o.files.unset(),
          ],
        );
        final stored = await raw(id);
        for (final key in nullableKeys) {
          expect(stored, isNot(contains(key)), reason: key);
        }
        expect(
          wire((await posts.get(id)).data),
          sameAs(minimalOf(full(alice, bob))),
        );
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
            o.buckets.set(x.buckets),
            o.dates.set(x.dates!),
            o.spots.set(x.spots!),
            o.files.set(x.files!),
          ],
        );
        expect(wire((await posts.get(id)).data), {
          ...wire(x),
          'thumb': wire(minimal(alice))['thumb'],
          'data': null,
        });
      });

      test(
        'set Bytes',
        skip: backend.isPostgres ? noBytesUpdate : null,
        () async {
          final id = (await posts.create(minimal(alice))).id;
          final x = full(alice, bob);
          await posts.update(
            id,
            (o) => [o.thumbnail.set(x.thumbnail), o.data.set(x.data!)],
          );
          final got = (await posts.get(id)).data;
          expect(got.thumbnail, x.thumbnail);
          expect(got.data, x.data);
        },
      );

      test('relation add and remove', () async {
        final id = (await posts.create(minimal(alice))).id;
        await posts.update(
          id,
          (o) => [
            o.followers.add([alice, bob]),
          ],
        );
        expect(
          await backend.relatedIds('Post', id, 'followers', '_User'),
          unorderedEquals([alice.id, bob.id]),
        );

        await posts.update(
          id,
          (o) => [
            o.followers.remove([bob]),
          ],
        );
        expect(await backend.relatedIds('Post', id, 'followers', '_User'), [
          alice.id,
        ]);
      });

      test('update returns the new updatedAt', () async {
        final created = await posts.create(minimal(alice));
        final updatedAt = (await posts.update(
          created.id,
          (o) => [o.likes.increment(1)],
        )).updatedAt;
        expect(updatedAt.isAfter(created.createdAt), isTrue);
        expect((await posts.get(created.id)).updatedAt, updatedAt);
      });
    });

    test(
      'replace overwrites every field and keeps relations',
      skip: backend.isPostgres ? noBytesUpdate : null,
      () async {
        final id = (await posts.create(full(alice, bob))).id;
        await posts.update(
          id,
          (o) => [
            o.followers.add([bob]),
          ],
        );
        final x = minimal(bob);
        final updatedAt = (await posts.replace(id, x)).updatedAt;

        final got = await posts.get(id);
        expect(wire(got.data), sameAs(x));
        expect(got.updatedAt, updatedAt);
        final stored = await raw(id);
        for (final key in nullableKeys) {
          expect(stored, isNot(contains(key)), reason: key);
        }
        expect(await backend.relatedIds('Post', id, 'followers', '_User'), [
          bob.id,
        ]);
      },
    );

    test('replace sends null fields as Delete', () async {
      final notes = client.collection(const $NoteSchema());
      final id = (await notes.create(
        Note(text: 'a', place: GeoPoint(1, 2)),
      )).id;
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
      test(
        'a missing id is ObjectNotFound from get, update and delete',
        () async {
          await expectLater(
            posts.get('doesNotExist'),
            throwsA(isA<ObjectNotFound>()),
          );
          await expectLater(
            posts.update('doesNotExist', (o) => [o.likes.increment(1)]),
            throwsA(isA<ObjectNotFound>()),
          );
          await expectLater(
            posts.delete('doesNotExist'),
            throwsA(isA<ObjectNotFound>()),
          );
        },
      );

      group('an update the ACL denies is ObjectNotFound (101), not 403', () {
        late String id;

        setUp(() async {
          final asAlice = backend.client();
          addTearDown(asAlice.close);
          await asAlice.auth(const $UserSchema()).become(aliceToken);
          id =
              (await asAlice
                      .collection(postSchema)
                      .create(
                        minimal(alice),
                        acl: const Acl().withUser(alice.id, write: true),
                      ))
                  .id;
        });

        Future<void> deniedFor(ParseClient caller) async {
          await expectLater(
            caller
                .collection(postSchema)
                .update(id, (o) => [o.title.set('mine')]),
            throwsA(
              isA<ObjectNotFound>()
                  .having((e) => e.code, 'code', 101)
                  .having((e) => e.status, 'status', 404),
            ),
          );
          expect((await raw(id))['title'], 't');
        }

        test('logged in as another user', () async {
          final asBob = backend.client();
          addTearDown(asBob.close);
          await asBob.auth(const $UserSchema()).become(bobToken);
          await deniedFor(asBob);
        });
      });

      test('a wrong app id is Unauthorized', () async {
        final wrong = backend.client(appId: 'wrong-app-id');
        addTearDown(wrong.close);
        await expectLater(
          wrong.collection(postSchema).get('x'),
          throwsA(isA<Unauthorized>()),
        );
      });

      test('an unreachable host is NetworkError', () async {
        final unreachable = ParseClient(
          server: Uri.parse('http://127.0.0.1:9/parse'),
          appId: 'x',
        );
        addTearDown(unreachable.close);
        await expectLater(
          unreachable.collection(postSchema).get('x'),
          throwsA(isA<NetworkError>()),
        );
      });
    });

    group('batch', () {
      late Collection<Note, NoteFields, NoteOps> notes;
      setUp(() => notes = client.collection(const $NoteSchema()));

      Future<Map<String, Object?>> stored(String id) => backend.rest(
        'GET',
        '/classes/Note/$id',
        master: true,
        allowError: true,
      );

      Future<int> countText(String text) async {
        final r = await backend.rest(
          'GET',
          '/classes/Note',
          master: true,
          query: {'where': '{"text":"$text"}', 'count': '1', 'limit': '0'},
        );
        return r['count']! as int;
      }

      Future<
        ({
          Batch batch,
          List<String> ids,
          BatchOp<Doc<Note>> created,
          BatchOp<UpdateResult<Note>> updated,
          BatchOp<UpdateResult<Note>> missing,
          BatchOp<UpdateResult<Note>> replaced,
          BatchOp<void> deleted,
        })
      >
      mixed(ParseClient via, String text) async {
        final ids = [
          for (final t in ['a', 'b', 'd'])
            (await notes.create(Note(text: t, place: GeoPoint(1, 2)))).id,
        ];
        final batchNotes = via.collection(const $NoteSchema());
        final batch = via.batch();
        return (
          batch: batch,
          ids: ids,
          created: batch.create(batchNotes, Note(text: text, draft: true)),
          updated: batch.update(
            batchNotes,
            ids[0],
            (o) => [o.place.set(GeoPoint(3, 4))],
          ),
          missing: batch.update(
            batchNotes,
            'doesNotExist',
            (o) => [o.place.set(GeoPoint(5, 6))],
          ),
          replaced: batch.replace(batchNotes, ids[1], const Note(text: 'rep')),
          deleted: batch.delete(batchNotes, ids[2]),
        );
      }

      test('one failing item is the only Err; the others apply', () async {
        final m = await mixed(client, 'new');
        await m.batch.send();

        expect(
          (m.missing.result as Err<UpdateResult<Note>>).error,
          isA<ObjectNotFound>().having((e) => e.status, 'status', 404),
        );
        final doc = (m.created.result as Ok<Doc<Note>>).value;
        // The beforeSave trigger in cloud/main.js uppercases text and unsets
        // draft; the batch response carries both changes.
        expect(doc.data.text, 'NEW');
        expect(doc.data.draft, isNull);
        expect((await notes.get(doc.id)).data.text, 'NEW');
        expect(m.updated.result, isA<Ok<UpdateResult<Note>>>());
        expect(m.replaced.result, isA<Ok<UpdateResult<Note>>>());
        expect(m.deleted.result, isA<Ok<void>>());

        expect((await notes.get(m.ids[0])).data.place, GeoPoint(3, 4));
        final replaced = await stored(m.ids[1]);
        expect(replaced['text'], 'REP');
        expect(replaced, isNot(contains('place')));
        expect((await stored(m.ids[2]))['code'], 101);
      });

      test('in a transaction one failing item applies none', () async {
        final m = await mixed(client, 'tx-new');
        await expectLater(
          m.batch.send(transaction: true),
          throwsA(
            isA<OtherParseError>()
                .having((e) => e.code, 'code', 1)
                .having((e) => e.status, 'status', 500),
          ),
        );
        expect(() => m.created.result, throwsStateError);
        // Right after the failure, on the same client: this call would get the
        // socket the server destroyed if the batch had kept its connection.
        expect((await notes.get(m.ids[0])).data.place, GeoPoint(1, 2));
        expect(await countText('TX-NEW'), 0);
        final kept = await notes.get(m.ids[1]);
        expect(kept.data.text, 'B');
        expect(kept.data.place, GeoPoint(1, 2));
        expect((await notes.get(m.ids[2])).data.text, 'D');
      });

      test('a transaction without a failing item applies all', () async {
        final id = (await notes.create(const Note(text: 'a'))).id;
        final b = client.batch();
        final created = b.create(notes, const Note(text: 'tx-ok'));
        final updated = b.update(notes, id, (o) => [o.text.set('tx-upd')]);
        await b.send(transaction: true);
        expect(created.result, isA<Ok<Doc<Note>>>());
        expect(updated.result, isA<Ok<UpdateResult<Note>>>());
        expect(await countText('TX-OK'), 1);
        expect((await notes.get(id)).data.text, 'TX-UPD');
      });
    });

    group('server values after a write', () {
      test('update: computed results and trigger changes', () async {
        final before = await posts.create(
          minimal(alice, tags: ['x'], ranks: [1, 2]),
        );
        final result = await posts.update(
          before.id,
          (o) => [
            o.title.set('new'),
            o.likes.increment(5),
            o.tags.addUnique(['x', 'y']),
            o.ranks.remove([1]),
          ],
        );
        final after = result.applyTo(before);
        final got = await posts.get(before.id);
        expect(wire(after.data), wire(got.data));
        expect(after.data.likes, 5);
        expect(after.data.tags, ['x', 'y']);
        expect(after.updatedAt, got.updatedAt);

        final notes = client.collection(const $NoteSchema());
        final note = await notes.create(const Note(text: 'a'));
        final changed = (await notes.update(
          note.id,
          (o) => [o.text.set('quiet'), o.draft.set(true)],
        )).applyTo(note);
        expect(changed.data.text, 'QUIET');
        expect(changed.data.draft, isNull);
        expect(
          noteWire(changed.data),
          noteWire((await notes.get(note.id)).data),
        );
      });

      test('replace: trigger changes too', () async {
        final notes = client.collection(const $NoteSchema());
        final note = await notes.create(const Note(text: 'a'));
        final changed = (await notes.replace(
          note.id,
          Note(text: 'loud', draft: true, place: GeoPoint(1, 1)),
        )).applyTo(note);
        expect(changed.data.text, 'LOUD');
        expect(changed.data.draft, isNull);
        expect(
          noteWire(changed.data),
          noteWire((await notes.get(note.id)).data),
        );
      });

      test('a batch update result applies the same way', () async {
        final before = await posts.create(minimal(alice));
        final b = client.batch();
        final op = b.update(posts, before.id, (o) => [o.likes.increment(2)]);
        await b.send();
        final after = (op.result as Ok<UpdateResult<Post>>).value.applyTo(
          before,
        );
        expect(after.data.likes, 2);
        expect(wire(after.data), wire((await posts.get(before.id)).data));
      });
    });

    group('map values', () {
      final at = DateTime.utc(2024, 5, 6, 7, 8, 9, 10);
      final where = GeoPoint(10, 20);
      const pic = ParseFile(name: 'p.png', url: 'http://files.test/p.png');

      test('typed values round-trip at any depth', () async {
        final meta = <String, Object?>{
          'at': at,
          'list': [at, where, 1, 'two', null],
          'nested': {'pic': pic, 'n': 1.5, 'ok': true},
        };
        final doc = await posts.create(minimal(alice, meta: meta));
        final got = (await posts.get(doc.id)).data.meta;
        expect(got['at'], at);
        expect(got['list'], [at, where, 1, 'two', null]);
        expect((got['nested']! as Map<String, Object?>)['pic'], pic);
        expect((got['nested']! as Map<String, Object?>)['n'], 1.5);
      });

      test('setKey, incrementKey and unsetKey change one key', () async {
        var doc = await posts.create(
          minimal(alice, meta: {'n': 1, 'keep': 'k', 'gone': true}),
        );
        for (final List<Op> Function(PostOps) build in [
          (o) => [o.meta.incrementKey('n', 2)],
          (o) => [o.meta.setKey('at', at)],
          (o) => [o.meta.unsetKey('gone')],
        ]) {
          doc = (await posts.update(doc.id, build)).applyTo(doc);
          expect(doc.data.meta, (await posts.get(doc.id)).data.meta);
        }
        expect(doc.data.meta, {'n': 3, 'keep': 'k', 'at': at});
      });

      test('a key inside the map is a query field', () async {
        final mark = 'mark-${DateTime.now().microsecondsSinceEpoch}';
        final hit = await posts.create(
          minimal(alice, meta: {'mark': mark, 'n': 7}),
        );
        await posts.create(minimal(alice, meta: {'mark': mark, 'n': 1}));
        final found = await posts
            .where((f) => f.meta.at('mark').eq(mark) & f.meta.at('n').gt(5))
            .find();
        expect([for (final d in found) d.id], [hit.id]);
      });

      test('values the server would store wrongly are not sent', () async {
        final count = await posts.query().count();
        for (final bad in <Map<String, Object?>>[
          {'bytes': Uint8List(1)},
          {'__op': 'Delete'},
          {
            'nested': {'__type': 'Date'},
          },
          {'n': double.nan},
          {'n': 9007199254740993},
        ]) {
          await expectLater(
            posts.create(minimal(alice, meta: bad)),
            throwsArgumentError,
          );
        }
        await expectLater(
          posts.create(minimal(alice, likes: 9007199254740993)),
          throwsArgumentError,
        );
        expect(await posts.query().count(), count);
      });
    });

    group('write options', () {
      test('a custom id, from create and from a batch', () async {
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final doc = await posts.create(minimal(alice), id: 'own$stamp');
        expect(doc.id, 'own$stamp');
        expect((await posts.get('own$stamp')).id, 'own$stamp');

        final b = client.batch();
        final op = b.create(posts, minimal(alice), id: 'batch$stamp');
        await b.send();
        expect((op.result as Ok<Doc<Post>>).value.id, 'batch$stamp');
        expect((await posts.get('batch$stamp')).id, 'batch$stamp');
      });

      test('context reaches every trigger of the write', () async {
        Future<Object?> contextOf(String trigger) async => (await backend.rest(
          'POST',
          '/functions/contextOf',
          body: {'trigger': '$trigger Post'},
        ))['result'];

        final stamp = DateTime.now().microsecondsSinceEpoch;
        final at = DateTime.utc(2024);
        final doc = await posts.create(
          minimal(alice),
          context: {'step': 'create $stamp', 'at': at},
        );
        expect(await contextOf('beforeSave'), {
          'step': 'create $stamp',
          'at': encodeDate(at),
        });
        expect(await contextOf('afterSave'), {
          'step': 'create $stamp',
          'at': encodeDate(at),
        });

        await posts.update(
          doc.id,
          (o) => [o.likes.set(1)],
          context: {'step': 'update $stamp'},
        );
        expect(await contextOf('beforeSave'), {'step': 'update $stamp'});

        // Post has a required Bytes field, which Postgres cannot update.
        if (!backend.isPostgres) {
          await posts.replace(
            doc.id,
            minimal(alice),
            context: {'step': 'replace $stamp'},
          );
          expect(await contextOf('afterSave'), {'step': 'replace $stamp'});
        }

        final b = client.batch();
        b.update(posts, doc.id, (o) => [o.likes.set(2)]);
        await b.send(context: {'step': 'batch $stamp'});
        expect(await contextOf('beforeSave'), {'step': 'batch $stamp'});

        await posts.delete(doc.id, context: {'step': 'delete $stamp'});
        expect(await contextOf('beforeDelete'), {'step': 'delete $stamp'});
        expect(await contextOf('afterDelete'), {'step': 'delete $stamp'});
      });

      test('45 batch items go in three requests and all apply', () async {
        final notes = client.collection(const $NoteSchema());
        final text = 'chunk-${DateTime.now().microsecondsSinceEpoch}';
        final b = client.batch();
        final ops = [
          for (var i = 0; i < 45; i++) b.create(notes, Note(text: '$text$i')),
        ];
        await b.send();
        expect(ops.map((o) => o.result), everyElement(isA<Ok<Doc<Note>>>()));
        expect(
          await notes
              .where((f) => f.text.startsWith(text.toUpperCase()))
              .count(),
          45,
        );
      });
    });

    group('more conditions', () {
      test(
        'a file field eq and ne',
        skip: backend.isPostgres
            ? 'Postgres has no equality for files (buildWhereClause in '
                  'PostgresStorageAdapter.js)'
            : null,
        () async {
          final name = 'eq${DateTime.now().microsecondsSinceEpoch}.png';
          final doc = await posts.create(minimal(alice, cover: file(name)));
          final found = await posts.where((f) => f.cover.eq(file(name))).find();
          expect([for (final d in found) d.id], [doc.id]);
          expect(
            await posts
                .where((f) => f.cover.ne(file(name)) & f.id.eq(doc.id))
                .count(),
            0,
          );
        },
      );

      test('a polygon that contains a point', () async {
        final square = Polygon([
          GeoPoint(40, 40),
          GeoPoint(40, 41),
          GeoPoint(41, 41),
          GeoPoint(41, 40),
        ]);
        final doc = await posts.create(minimal(alice, area: square));
        final inside = await posts
            .where((f) => f.area.containsPoint(GeoPoint(40.5, 40.5)))
            .find();
        expect([for (final d in inside) d.id], contains(doc.id));
        final outside = await posts
            .where((f) => f.area.containsPoint(GeoPoint(45, 45)))
            .find();
        expect([for (final d in outside) d.id], isNot(contains(doc.id)));
        expect(square.containsPoint(GeoPoint(40.5, 40.5)), isTrue);
      });

      test('include through two pointers', () async {
        await resetSignals(backend);
        final all = client.collection(signals);
        final a = await all.create(const Signal(name: 'a'));
        final b = await all.create(Signal(name: 'b', links: [Pointer(a.id)]));
        final c = await all.create(Signal(name: 'c', links: [Pointer(b.id)]));
        final got = await all
            .query()
            .include((f) => f.links.then((l) => l.links))
            .get(c.id);
        final first = got.data.links!.single.loaded!;
        expect(first.id, b.id);
        expect(first.data.links!.single.loaded!.data.name, 'a');

        final one = await all.query().include((f) => f.links).get(c.id);
        expect(
          one.data.links!.single.loaded!.data.links!.single.loaded,
          isNull,
        );
      });
    });

    group('files', () {
      late ParseClient asAlice;
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 1, 255]);

      setUpAll(() async {
        asAlice = backend.client();
        await asAlice.auth(const $UserSchema()).become(aliceToken);
      });

      tearDownAll(() => asAlice.close());

      test('an upload in a File field round-trips through get', () async {
        final file = await asAlice.uploadFile(
          png,
          name: 'cover.png',
          contentType: 'image/png',
        );
        final id = (await posts.create(minimal(alice, cover: file))).id;
        final got = (await posts.get(id)).data.cover;
        expect(got, file);
        expect(got.url, file.url);
      });

      test('an upload in a File field passes a beforeSave', () async {
        final file = await asAlice.uploadFile(
          png,
          name: 'cover.png',
          contentType: 'image/png',
        );
        final notes = client.collection(const $NoteSchema());
        final id = (await notes.create(Note(text: 'a', attachment: file))).id;
        expect((await notes.get(id)).data.attachment?.url, file.url);
      });

      test('metadata and tags reach the file trigger', () async {
        await asAlice.uploadFile(
          png,
          name: 'meta.png',
          contentType: 'image/png',
          metadata: {'owner': 'alice'},
          tags: {'kind': 'avatar'},
        );
        final saved = (await backend.rest(
          'POST',
          '/functions/savedFile',
          body: {},
        ))['result'];
        expect(saved, {
          'metadata': {'owner': 'alice'},
          'tags': {'kind': 'avatar'},
        });
      });

      test('progress covers every byte, and download returns them', () async {
        final big = Uint8List.fromList(
          List.generate(300 * 1024, (i) => i % 251),
        );
        final seen = <int>[];
        final file = await asAlice.uploadFile(
          big,
          name: 'big.bin',
          contentType: 'application/octet-stream',
          onProgress: (sent, total) {
            expect(total, big.length);
            seen.add(sent);
          },
        );
        expect(seen, hasLength(greaterThan(1)));
        expect(seen, [...seen]..sort());
        expect(seen.last, big.length);
        expect(await asAlice.downloadFile(file), big);
      });

      test('a completed cancel aborts the upload', () async {
        await expectLater(
          asAlice.uploadFile(
            Uint8List(1024 * 1024),
            name: 'cancelled.bin',
            contentType: 'application/octet-stream',
            cancel: Future.value(),
          ),
          throwsA(isA<NetworkError>()),
        );
      });
    });
  });
}

const noBytesUpdate =
    'Postgres rejects any update that writes a Bytes value '
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
  'dates',
  'spots',
  'files',
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
  buckets: p.buckets,
);
