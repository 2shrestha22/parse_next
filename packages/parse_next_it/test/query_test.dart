import 'dart:convert';
import 'dart:math';

import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/item.dart';
import 'package:parse_next_it/models/user.dart';
import 'package:test/test.dart';

import 'support.dart';

const itemSchema = $ItemSchema();
const fields = ItemFields();
const vocabulary = ['amber', 'birch', 'cedar', 'delta', 'ember', 'fjord'];

typedef Person = ({Pointer<User> user, int karma});

final class Seeded {
  Seeded(this.docs, this.people, this.users, this.backend);

  final List<Doc<Item>> docs;
  final List<Person> people;
  final Collection<User, UserFields, UserOps> users;
  final Backend backend;

  Item operator [](int i) => docs[i].data;
  Pointer<User> person(int i) => people[i].user;
}

typedef Case = ({
  String name,
  Cond<Item> Function(ItemFields f, Seeded s) cond,
  bool Function(Doc<Item> d, Seeded s) test,
});

Case c(
  String name,
  Cond<Item> Function(ItemFields f, Seeded s) cond,
  bool Function(Doc<Item> d, Seeded s) test,
) => (name: name, cond: cond, test: test);

bool inList<V>(List<V> list, V v) => list.contains(v);

double km(GeoPoint a, GeoPoint b) {
  double rad(double d) => d * pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h =
      pow(sin(dLat / 2), 2) +
      cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLng / 2), 2);
  return 2 * 6371 * asin(sqrt(h));
}

bool inPolygon(GeoPoint p, Polygon poly) {
  var inside = false;
  final pts = poly.points;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final (xi, yi) = (pts[i].longitude, pts[i].latitude);
    final (xj, yj) = (pts[j].longitude, pts[j].latitude);
    if ((yi > p.latitude) != (yj > p.latitude) &&
        p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

final origin = GeoPoint(0, 0);
final southwest = GeoPoint(-20, -40);
final northeast = GeoPoint(30, 60);
final triangle = Polygon([
  GeoPoint(-30, -100),
  GeoPoint(40, -20),
  GeoPoint(-10, 90),
]);
const nearKm = 3000.0;

final cases = <Case>[
  c(
    'name eq',
    (f, s) => f.name.eq(s[0].name),
    (d, s) => d.data.name == s[0].name,
  ),
  c(
    'name ne',
    (f, s) => f.name.ne(s[0].name),
    (d, s) => d.data.name != s[0].name,
  ),
  c(
    'name oneOf',
    (f, s) => f.name.oneOf([s[1].name, s[2].name, s[3].name]),
    (d, s) => inList([s[1].name, s[2].name, s[3].name], d.data.name),
  ),
  c(
    'name noneOf',
    (f, s) => f.name.noneOf([s[1].name, s[2].name]),
    (d, s) => !inList([s[1].name, s[2].name], d.data.name),
  ),
  c(
    'name gt',
    (f, s) => f.name.gt('cc'),
    (d, s) => d.data.name.compareTo('cc') > 0,
  ),
  c(
    'name gte',
    (f, s) => f.name.gte(s[4].name),
    (d, s) => d.data.name.compareTo(s[4].name) >= 0,
  ),
  c(
    'name lt',
    (f, s) => f.name.lt('bb'),
    (d, s) => d.data.name.compareTo('bb') < 0,
  ),
  c(
    'name lte',
    (f, s) => f.name.lte(s[6].name),
    (d, s) => d.data.name.compareTo(s[6].name) <= 0,
  ),
  c(
    'name startsWith',
    (f, s) => f.name.startsWith('ab'),
    (d, s) => d.data.name.startsWith('ab'),
  ),
  c(
    'name matches',
    (f, s) => f.name.matches('a.c'),
    (d, s) => RegExp('a.c').hasMatch(d.data.name),
  ),
  c(
    'name matches anchored at the end',
    (f, s) => f.name.matches(r'f$'),
    (d, s) => d.data.name.endsWith('f'),
  ),
  c(
    'name matches caseInsensitive',
    (f, s) => f.name.matches('^B', caseInsensitive: true),
    (d, s) => d.data.name.startsWith('b'),
  ),
  c('note exists', (f, s) => f.note.exists(), (d, s) => d.data.note != null),
  c(
    'note exists false',
    (f, s) => f.note.exists(false),
    (d, s) => d.data.note == null,
  ),
  c(
    'note eq',
    (f, s) => f.note.eq(s.docs.firstNote),
    (d, s) => d.data.note == s.docs.firstNote,
  ),
  c(
    'note ne',
    (f, s) => f.note.ne(s.docs.firstNote),
    (d, s) => d.data.note != s.docs.firstNote,
  ),
  c(
    'note noneOf',
    (f, s) => f.note.noneOf([s.docs.firstNote]),
    (d, s) => s.backend.isPostgres
        ? d.data.note != null && d.data.note != s.docs.firstNote
        : d.data.note != s.docs.firstNote,
  ),
  c(
    'note fullText',
    (f, s) => f.note.fullText('amber'),
    (d, s) => d.data.note?.split(' ').contains('amber') ?? false,
  ),
  c('rank eq', (f, s) => f.rank.eq(7), (d, s) => d.data.rank == 7),
  c('rank ne', (f, s) => f.rank.ne(7), (d, s) => d.data.rank != 7),
  c(
    'rank oneOf',
    (f, s) => f.rank.oneOf([1, 2, 3]),
    (d, s) => inList([1, 2, 3], d.data.rank),
  ),
  c(
    'rank noneOf',
    (f, s) => f.rank.noneOf([1, 2, 3]),
    (d, s) => !inList([1, 2, 3], d.data.rank),
  ),
  c('rank gt', (f, s) => f.rank.gt(30), (d, s) => d.data.rank > 30),
  c('rank gte', (f, s) => f.rank.gte(30), (d, s) => d.data.rank >= 30),
  c('rank lt', (f, s) => f.rank.lt(10), (d, s) => d.data.rank < 10),
  c('rank lte', (f, s) => f.rank.lte(10), (d, s) => d.data.rank <= 10),
  c(
    'score gt',
    (f, s) => f.score.gt(0.5),
    (d, s) => (d.data.score ?? -1) > 0.5,
  ),
  c(
    'score lte',
    (f, s) => f.score.lte(0.25),
    (d, s) => d.data.score != null && d.data.score! <= 0.25,
  ),
  c(
    'score exists false',
    (f, s) => f.score.exists(false),
    (d, s) => d.data.score == null,
  ),
  c('at gt', (f, s) => f.at.gt(s[0].at), (d, s) => d.data.at.isAfter(s[0].at)),
  c(
    'at lte',
    (f, s) => f.at.lte(s[0].at),
    (d, s) => !d.data.at.isAfter(s[0].at),
  ),
  c('at eq', (f, s) => f.at.eq(s[3].at), (d, s) => d.data.at == s[3].at),
  c(
    'kind eq',
    (f, s) => f.kind.eq(Kind.red),
    (d, s) => d.data.kind == Kind.red,
  ),
  c(
    'kind ne',
    (f, s) => f.kind.ne(Kind.red),
    (d, s) => d.data.kind != Kind.red,
  ),
  c(
    'kind oneOf',
    (f, s) => f.kind.oneOf([Kind.red, Kind.blue]),
    (d, s) => d.data.kind != Kind.green,
  ),
  c(
    'kind noneOf',
    (f, s) => f.kind.noneOf([Kind.green]),
    (d, s) => d.data.kind != Kind.green,
  ),
  c('flag eq', (f, s) => f.flag.eq(true), (d, s) => d.data.flag),
  c('flag ne', (f, s) => f.flag.ne(true), (d, s) => !d.data.flag),
  c(
    'tags contains',
    (f, s) => f.tags.contains('a'),
    (d, s) => d.data.tags.contains('a'),
  ),
  c(
    'tags containsAll',
    (f, s) => f.tags.containsAll(['a', 'b']),
    (d, s) => d.data.tags.contains('a') && d.data.tags.contains('b'),
  ),
  c(
    'tags containsAny',
    (f, s) => f.tags.containsAny(['a', 'd']),
    (d, s) => d.data.tags.contains('a') || d.data.tags.contains('d'),
  ),
  c(
    'owner isId',
    (f, s) => f.owner.isId(s.person(0).id),
    (d, s) => d.data.owner.id == s.person(0).id,
  ),
  c(
    'owner matchesQuery',
    (f, s) => f.owner.matchesQuery(
      s.users.where(
        (u) =>
            u.karma.gte(3) & u.id.oneOf([for (final p in s.people) p.user.id]),
      ),
    ),
    (d, s) => s.people
        .where((p) => p.karma >= 3)
        .any((p) => p.user.id == d.data.owner.id),
  ),
  c(
    'helpers contains',
    (f, s) => f.helpers.contains(s.person(1)),
    (d, s) => d.data.helpers.any((p) => p.id == s.person(1).id),
  ),
  c(
    'helpers containsAll',
    (f, s) => f.helpers.containsAll([s.person(1), s.person(2)]),
    (d, s) =>
        d.data.helpers.any((p) => p.id == s.person(1).id) &&
        d.data.helpers.any((p) => p.id == s.person(2).id),
  ),
  c(
    'helpers containsAny',
    (f, s) => f.helpers.containsAny([s.person(1), s.person(2)]),
    (d, s) => d.data.helpers.any(
      (p) => p.id == s.person(1).id || p.id == s.person(2).id,
    ),
  ),
  c(
    'spot near',
    (f, s) => f.spot.near(origin, maxKm: nearKm),
    (d, s) => km(origin, d.data.spot) <= nearKm,
  ),
  c('spot withinBox', (f, s) => f.spot.withinBox(southwest, northeast), (d, s) {
    final p = d.data.spot;
    return p.latitude >= southwest.latitude &&
        p.latitude <= northeast.latitude &&
        p.longitude >= southwest.longitude &&
        p.longitude <= northeast.longitude;
  }),
  c(
    'spot withinPolygon',
    (f, s) => f.spot.withinPolygon(triangle),
    (d, s) => inPolygon(d.data.spot, triangle),
  ),
  c('id eq', (f, s) => f.id.eq(s.docs[9].id), (d, s) => d.id == s.docs[9].id),
  c(
    'id oneOf',
    (f, s) => f.id.oneOf([for (final d in s.docs.take(5)) d.id]),
    (d, s) => s.docs.take(5).any((x) => x.id == d.id),
  ),
  c(
    'createdAt gt',
    (f, s) => f.createdAt.gt(s.docs[100].createdAt),
    (d, s) => d.createdAt.isAfter(s.docs[100].createdAt),
  ),
  c(
    'createdAt lte',
    (f, s) => f.createdAt.lte(s.docs[100].createdAt),
    (d, s) => !d.createdAt.isAfter(s.docs[100].createdAt),
  ),
];

extension on List<Doc<Item>> {
  String get firstNote => map((d) => d.data.note).nonNulls.first;
}

/// Why a pair cannot run on [backend], or null when it can.
String? unsupportedPair(Backend backend, Case a, Case b, String op) {
  if (backend.isPostgres) return null;
  final names = {a.name, b.name};
  if (names.containsAll(['spot near', 'note fullText'])) return mongoTextNear;
  if (op != '|') return null;
  if (names.contains('spot near')) return mongoNearInOr;
  if (names.contains('note fullText')) return mongoTextInOr;
  return null;
}

const mongoNearInOr =
    r'MongoDB rejects $nearSphere inside $or '
    '(parse-server answers 500); MongoTransform.js passes it through';
const mongoTextNear =
    r'MongoDB rejects $text together with $nearSphere in '
    'one query (parse-server answers 500)';
const mongoTextInOr =
    r'MongoDB rejects $text inside $or unless every clause '
    'is text-indexed (parse-server answers 500)';

List<Item> generate(Random r, int n, List<Person> people) => [
  for (var i = 0; i < n; i++)
    Item(
      name: String.fromCharCodes([
        for (var k = 0; k < 3 + r.nextInt(3); k++)
          'abcdef'.codeUnitAt(r.nextInt(6)),
      ]),
      note: r.nextInt(4) == 0
          ? null
          : '${vocabulary[r.nextInt(6)]} ${vocabulary[r.nextInt(6)]}',
      rank: r.nextInt(50),
      score: r.nextInt(4) == 0 ? null : r.nextDouble(),
      at: DateTime.utc(2020).add(Duration(minutes: r.nextInt(1000000))),
      kind: Kind.values[r.nextInt(3)],
      flag: r.nextBool(),
      tags: [
        for (final t in ['a', 'b', 'c', 'd'])
          if (r.nextDouble() < 0.4) t,
      ],
      owner: people[r.nextInt(people.length)].user,
      helpers: [
        for (final p in people)
          if (r.nextDouble() < 0.3) p.user,
      ],
      spot: GeoPoint(r.nextDouble() * 120 - 60, r.nextDouble() * 340 - 170),
    ),
];

Future<List<R>> inBatches<T, R>(
  List<T> items,
  Future<R> Function(T) run,
) async {
  final out = <R>[];
  for (var i = 0; i < items.length; i += 20) {
    out.addAll(await Future.wait(items.skip(i).take(20).map(run)));
  }
  return out;
}

Future<void> resetItems(Backend backend) {
  Map<String, String> type(String t) => {'type': t};
  const user = {'type': 'Pointer', 'targetClass': '_User'};
  return backend.resetClass('Item', {
    for (final k in ['name', 'note', 'kind']) k: type('String'),
    for (final k in ['rank', 'score']) k: type('Number'),
    'happened_at': type('Date'),
    'flag': type('Boolean'),
    for (final k in ['tags', 'helpers']) k: type('Array'),
    'owner': user,
    'spot': type('GeoPoint'),
    'fans': {...user, 'type': 'Relation'},
  });
}

Set<String> ids(Iterable<Doc<Item>> docs) => {for (final d in docs) d.id};

void main() {
  forEachBackend((backend) {
    late ParseClient client;
    late Collection<Item, ItemFields, ItemOps> items;
    late Collection<User, UserFields, UserOps> users;
    late List<Person> people;

    setUpAll(() async {
      client = backend.client();
      items = client.collection(itemSchema);
      users = client.collection(const $UserSchema());
      people = [
        for (var k = 0; k < 5; k++)
          (
            user: Pointer<User>(
              (await backend.signUp('person$k', {'karma': k})).id,
            ),
            karma: k,
          ),
      ];
    });

    tearDownAll(() => client.close());

    group('oracle', () {
      late Seeded s;

      setUpAll(() async {
        await resetItems(backend);
        final docs = await inBatches(
          generate(Random(42), 200, people),
          items.create,
        );
        s = Seeded(docs, people, users, backend);
      });

      Future<List<Doc<Item>>> all(Query<Item, ItemFields, ItemOps> q) =>
          q.limit(1000).find();

      Set<String> expected(bool Function(Doc<Item> d) test) =>
          ids(s.docs.where(test));

      group('each constraint', () {
        for (final x in cases) {
          test(x.name, () async {
            final want = expected((d) => x.test(d, s));
            expect(
              want.length,
              inExclusiveRange(0, 200),
              reason:
                  'a case that matches no row or every row proves '
                  'nothing',
            );
            final q = items.where((f) => x.cond(f, s));
            expect(ids(await all(q)), want);
            expect(await q.count(), want.length);
          });
        }
      });

      for (final op in ['&', '|']) {
        group('every pair with $op', () {
          for (var i = 0; i < cases.length; i++) {
            final a = cases[i];
            final partners = cases.skip(i + 1).toList();
            final skipped = {
              for (final b in partners)
                b.name: ?unsupportedPair(backend, a, b, op),
            };
            test('${a.name} $op each later constraint', () async {
              final failures = <String>[];
              await inBatches(
                partners.where((b) => !skipped.containsKey(b.name)).toList(),
                (b) async {
                  final q = items.where(
                    (f) => op == '&'
                        ? a.cond(f, s) & b.cond(f, s)
                        : a.cond(f, s) | b.cond(f, s),
                  );
                  final want = expected(
                    (d) => op == '&'
                        ? a.test(d, s) && b.test(d, s)
                        : a.test(d, s) || b.test(d, s),
                  );
                  try {
                    final got = ids(await all(q));
                    if (got.length != want.length || !got.containsAll(want)) {
                      failures.add(
                        '${b.name}: got ${got.length}, '
                        'want ${want.length}',
                      );
                    }
                  } on ParseException catch (e) {
                    failures.add('${b.name}: $e');
                  }
                },
              );
              expect(failures, isEmpty);
            });
            for (final reason in skipped.values.toSet()) {
              final names = [
                for (final e in skipped.entries)
                  if (e.value == reason) e.key,
              ];
              test('${a.name} $op ${names.join(', ')}', skip: reason, () {});
            }
          }
        });
      }

      group('sort', () {
        String rank(Doc<Item> d) => d.data.rank.toString().padLeft(2, '0');
        for (final (
              name,
              Sort<Item> Function(ItemFields f) sort,
              String Function(Doc<Item> d) key,
              bool desc,
            )
            in [
              ('name asc', (f) => f.name.asc, (d) => d.data.name, false),
              ('name desc', (f) => f.name.desc, (d) => d.data.name, true),
              ('rank asc', (f) => f.rank.asc, rank, false),
              ('rank desc', (f) => f.rank.desc, rank, true),
              (
                'at asc',
                (f) => f.at.asc,
                (d) => d.data.at.toIso8601String(),
                false,
              ),
              (
                'at desc',
                (f) => f.at.desc,
                (d) => d.data.at.toIso8601String(),
                true,
              ),
              (
                'createdAt asc',
                (f) => f.createdAt.asc,
                (d) => d.createdAt.toIso8601String(),
                false,
              ),
              (
                'createdAt desc',
                (f) => f.createdAt.desc,
                (d) => d.createdAt.toIso8601String(),
                true,
              ),
            ]) {
          test(name, () async {
            final got = await all(items.query().orderBy(sort));
            final want = [...s.docs.map(key)]..sort();
            expect(got.map(key).toList(), desc ? want.reversed.toList() : want);
            expect(ids(got), ids(s.docs));
          });
        }

        String pairKey(Doc<Item> d) => '${rank(d)} ${d.data.name}';

        test('rank asc then name desc', () async {
          final got = await all(
            items
                .query()
                .orderBy((f) => f.rank.asc)
                .orderBy((f) => f.name.desc),
          );
          final want = [...s.docs]
            ..sort((x, y) {
              final r = x.data.rank.compareTo(y.data.rank);
              return r != 0 ? r : y.data.name.compareTo(x.data.name);
            });
          expect(got.map(pairKey).toList(), want.map(pairKey).toList());
        });

        test('with where, skip and limit', () async {
          final got = await items
              .where((f) => f.flag.eq(true))
              .orderBy((f) => f.rank.desc)
              .skip(10)
              .limit(20)
              .find();
          final want = [
            for (final d in s.docs)
              if (d.data.flag) d.data.rank,
          ]..sort((x, y) => y.compareTo(x));
          expect(
            got.map((d) => d.data.rank).toList(),
            want.skip(10).take(20).toList(),
          );
        });

        test(
          'an absent value sorts first on Mongo and last on Postgres',
          () async {
            final got = await all(items.query().orderBy((f) => f.score.asc));
            final scores = got.map((d) => d.data.score).toList();
            final nulls = s.docs.where((d) => d.data.score == null).length;
            final present = scores.nonNulls.toList();
            expect(present, [...present]..sort());
            expect(
              scores,
              backend.isPostgres
                  ? [...present, for (var i = 0; i < nulls; i++) null]
                  : [for (var i = 0; i < nulls; i++) null, ...present],
            );
          },
        );
      });

      test('find without a limit sends limit=100', () async {
        expect(await items.query().find(), hasLength(100));
      });

      test('first and count', () async {
        final want = s.docs.where((d) => d.data.rank == 7).toList();
        final got = await items
            .where((f) => f.rank.eq(7))
            .orderBy((f) => f.at.asc)
            .first();
        expect(
          got!.data.at,
          want.map((d) => d.data.at).reduce((a, b) => a.isBefore(b) ? a : b),
        );
        expect(await items.where((f) => f.rank.eq(7)).count(), want.length);
        expect(await items.where((f) => f.rank.eq(-1)).first(), isNull);
        expect(await items.query().count(), 200);
      });

      test('raw returns only the listed keys', () async {
        final rows = await items.where((f) => f.rank.eq(7)).raw(keys: ['rank']);
        expect(rows, hasLength(s.docs.where((d) => d.data.rank == 7).length));
        for (final r in rows) {
          expect(r['rank'], 7);
          expect(r, isNot(contains('name')));
          expect(r['objectId'], isA<String>());
        }
      });

      test(
        'include loads a pointer and a pointer list, and only then',
        () async {
          final doc = s.docs.firstWhere((d) => d.data.helpers.length >= 2);
          final q = items.where((f) => f.id.eq(doc.id));

          final plain = (await q.first())!.data;
          expect(plain.owner.loaded, isNull);
          expect(plain.helpers.map((p) => p.loaded), everyElement(isNull));

          final owner = (await q.include((f) => f.owner).first())!.data;
          expect(owner.owner.loaded!.data.username, startsWith('person'));
          expect(owner.owner.loaded!.id, doc.data.owner.id);
          expect(owner.helpers.map((p) => p.loaded), everyElement(isNull));

          final both =
              (await q
                      .include((f) => f.owner)
                      .include((f) => f.helpers)
                      .first())!
                  .data;
          expect(both.owner.loaded, isNotNull);
          expect(
            [for (final p in both.helpers) p.loaded!.id],
            [for (final p in doc.data.helpers) p.id],
          );
          expect([
            for (final p in both.helpers) p.loaded!.data.karma,
          ], everyElement(isA<int>()));
        },
      );

      test('a relation condition lists the members', () async {
        final owner = s.docs[0].id;
        await items.update(
          owner,
          (o) => [
            o.fans.add([s.person(0), s.person(2)]),
          ],
        );
        final members = await users.where((_) => fields.fans.of(owner)).find();
        expect(
          {for (final d in members) d.id},
          {s.person(0).id, s.person(2).id},
        );

        final some = await users
            .where((f) => fields.fans.of(owner) & f.karma.gt(0))
            .find();
        expect([for (final d in some) d.id], [s.person(2).id]);
      });

      group('dates', () {
        test(
          'createdAt.gt sends __type Date and returns the later rows',
          () async {
            final pivot = s.docs[100].createdAt;
            final got = await all(items.where((f) => f.createdAt.gt(pivot)));
            expect(ids(got), expected((d) => d.createdAt.isAfter(pivot)));
            expect(got, isNotEmpty);
          },
        );

        for (final key in ['createdAt', 'happened_at']) {
          test('a plain ISO string on $key over raw HTTP', () async {
            final pivot = DateTime.utc(2000).toIso8601String();
            final r = await backend.rest(
              'GET',
              '/classes/Item',
              query: {
                'where': jsonEncode({
                  key: {r'$gt': pivot},
                }),
                'limit': '1000',
              },
            );
            final rows = r['results']! as List<Object?>;
            expect(rows, backend.isPostgres ? hasLength(200) : isEmpty);
          });
        }
      });
    });

    group('fullText', () {
      setUpAll(() async {
        await resetItems(backend);
        await inBatches(generate(Random(1), 5, people), items.create);
      });

      test('count before any find is a 500 on Mongo only', () async {
        Query<Item, ItemFields, ItemOps> q(ParseClient c) =>
            c.collection(itemSchema).where((f) => f.note.fullText('amber'));
        if (backend.isPostgres) {
          await q(client).count();
          return;
        }
        final failing = backend.client();
        await expectLater(
          q(failing).count(),
          throwsA(
            isA<OtherParseError>().having((e) => e.status, 'status', 500),
          ),
        );
        failing.close();
        // A fresh client: after an uncaught 500 parse-server destroys the
        // socket (handleParseErrors calls next(err) after responding), so
        // the next request on the pooled connection can fail.
        await q(client).find();
        expect(await q(client).count(), greaterThan(0));
      });
    });

    group('stream', () {
      late List<Doc<Item>> docs;

      setUpAll(() async {
        await resetItems(backend);
        docs = await inBatches(generate(Random(7), 1050, people), items.create);
      });

      test('1,050 objects with no duplicates and no gaps', () async {
        final got = await items.query().stream().map((d) => d.id).toList();
        expect(got.length, 1050);
        expect(got.toSet(), ids(docs));
      });

      test('with a where condition', () async {
        final got = await items
            .where((f) => f.rank.lt(25))
            .stream()
            .map((d) => d.id)
            .toList();
        final want = ids(docs.where((d) => d.data.rank < 25));
        expect(got.length, want.length);
        expect(got.toSet(), want);
      });
    });
  });
}
