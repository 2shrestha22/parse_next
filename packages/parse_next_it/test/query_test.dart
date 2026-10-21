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
  Seeded(this.docs, this.people, this.users, this.items, this.backend);

  final List<Doc<Item>> docs;
  final List<Person> people;
  final Collection<User, UserFields, UserOps> users;
  final Collection<Item, ItemFields, ItemOps> items;
  final Backend backend;

  Item operator [](int i) => docs[i].data;
  Pointer<User> person(int i) => people[i].user;
}

typedef Case = ({
  String name,
  Cond<Item> Function(ItemFields f, Seeded s) cond,
  bool Function(Doc<Item> d, Seeded s) test,
  String? postgres,
});

/// [postgres] is why the case cannot run there, if it cannot.
Case c(
  String name,
  Cond<Item> Function(ItemFields f, Seeded s) cond,
  bool Function(Doc<Item> d, Seeded s) test, {
  String? postgres,
}) => (name: name, cond: cond, test: test, postgres: postgres);

int karmaOf(Seeded s, Pointer<User> user) =>
    s.people.firstWhere((p) => p.user.id == user.id).karma;

Set<String> namesWithRank(Seeded s, int rank) => {
  for (final d in s.docs)
    if (d.data.rank == rank) d.data.name,
};

const postgresDateIn =
    r'Postgres passes a {"__type":"Date"} inside $ne, $in or $nin to SQL '
    'unconverted and answers 500 (buildWhereClause in '
    'PostgresStorageAdapter.js)';

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
    'owner eq',
    (f, s) => f.owner.eq(s.person(1)),
    (d, s) => d.data.owner.id == s.person(1).id,
  ),
  c(
    'owner ne',
    (f, s) => f.owner.ne(s.person(1)),
    (d, s) => d.data.owner.id != s.person(1).id,
  ),
  c(
    'owner oneOf',
    (f, s) => f.owner.oneOf([s.person(1), s.person(2)]),
    (d, s) => {s.person(1).id, s.person(2).id}.contains(d.data.owner.id),
  ),
  c(
    'owner noneOf',
    (f, s) => f.owner.noneOf([s.person(1), s.person(2)]),
    (d, s) => !{s.person(1).id, s.person(2).id}.contains(d.data.owner.id),
  ),
  c(
    'owner notMatchesQuery',
    (f, s) => f.owner.notMatchesQuery(
      s.users.where(
        (u) =>
            u.karma.gte(3) & u.id.oneOf([for (final p in s.people) p.user.id]),
      ),
    ),
    (d, s) => karmaOf(s, d.data.owner) < 3,
  ),
  c(
    'name matchesKey',
    (f, s) =>
        f.name.matchesKey(s.items.where((i) => i.rank.eq(7)), (i) => i.name),
    (d, s) => namesWithRank(s, 7).contains(d.data.name),
  ),
  c(
    'name notMatchesKey',
    (f, s) =>
        f.name.notMatchesKey(s.items.where((i) => i.rank.eq(7)), (i) => i.name),
    (d, s) => !namesWithRank(s, 7).contains(d.data.name),
  ),
  c('~ rank gt', (f, s) => ~f.rank.gt(30), (d, s) => !(d.data.rank > 30)),
  c(
    'name endsWith',
    (f, s) => f.name.endsWith('ab'),
    (d, s) => d.data.name.endsWith('ab'),
  ),
  c(
    'name contains',
    (f, s) => f.name.contains('fa'),
    (d, s) => d.data.name.contains('fa'),
  ),
  c(
    'tags containedBy',
    (f, s) => f.tags.containedBy(['a', 'b']),
    (d, s) => d.data.tags.every(['a', 'b'].contains),
  ),
  c(
    'tags containsAllStartingWith',
    (f, s) => f.tags.containsAllStartingWith(['a', 'c']),
    (d, s) => d.data.tags.contains('a') && d.data.tags.contains('c'),
  ),
  c(
    'spot withinKm',
    (f, s) => f.spot.withinKm(origin, nearKm),
    (d, s) => km(d.data.spot, origin) <= nearKm,
  ),
  c(
    'at ne',
    (f, s) => f.at.ne(s[3].at),
    (d, s) => d.data.at != s[3].at,
    postgres: postgresDateIn,
  ),
  c(
    'at oneOf',
    (f, s) => f.at.oneOf([s[3].at, s[4].at]),
    (d, s) => d.data.at == s[3].at || d.data.at == s[4].at,
    postgres: postgresDateIn,
  ),
  c(
    'at noneOf',
    (f, s) => f.at.noneOf([s[3].at]),
    (d, s) => d.data.at != s[3].at,
    postgres: postgresDateIn,
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
        s = Seeded(docs, people, users, items, backend);
      });

      Future<List<Doc<Item>>> all(Query<Item, ItemFields, ItemOps> q) =>
          q.limit(1000).find();

      Set<String> expected(bool Function(Doc<Item> d) test) =>
          ids(s.docs.where(test));

      group('each constraint', () {
        for (final x in cases) {
          test(x.name, skip: backend.isPostgres ? x.postgres : null, () async {
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

      test('& and | combine as the server expects', () async {
        for (final (Cond<Item> Function(ItemFields f) cond, test) in [
          // One key twice nests in $and.
          (
            (f) => f.tags.contains('a') & f.tags.contains('b'),
            (Doc<Item> d) =>
                d.data.tags.contains('a') && d.data.tags.contains('b'),
          ),
          // Mongo writes both as a top-level $nor.
          (
            (f) => f.tags.containedBy(['a', 'b']) & ~f.rank.gt(30),
            (Doc<Item> d) =>
                d.data.tags.every(['a', 'b'].contains) && d.data.rank <= 30,
          ),
          (
            (f) => f.rank.lt(5) | (f.flag.eq(true) & f.rank.gt(45)),
            (Doc<Item> d) =>
                d.data.rank < 5 || (d.data.flag && d.data.rank > 45),
          ),
        ]) {
          expect(ids(await all(items.where(cond))), expected(test));
        }
      });

      group('sort', () {
        String rank(Doc<Item> d) => d.data.rank.toString().padLeft(2, '0');

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
      });

      test('a where of 3,000 ids finds and counts its matches', () async {
        final ids = [
          for (var i = 0; i < 3000; i++)
            'absent${i.toString().padLeft(4, '0')}',
          s.docs[3].id,
          s.docs[5].id,
        ];
        final q = items.where((f) => f.id.oneOf(ids));
        expect(
          {for (final d in await q.find()) d.id},
          {s.docs[3].id, s.docs[5].id},
        );
        expect(await q.count(), 2);
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

      test('raw with exclude leaves those keys out', () async {
        final rows = await items
            .where((f) => f.rank.eq(7))
            .raw(exclude: ['name', 'note']);
        expect(rows, hasLength(s.docs.where((d) => d.data.rank == 7).length));
        for (final r in rows) {
          expect(r, isNot(contains('name')));
          expect(r, isNot(contains('note')));
          expect(r['rank'], 7);
        }
      });

      test('an empty oneOf or containsAny matches nothing, in | too', () async {
        expect(await items.where((f) => f.name.oneOf([])).count(), 0);
        expect(await items.where((f) => f.tags.containsAny([])).count(), 0);
        expect(
          ids(await all(items.where((f) => f.owner.oneOf([]) | f.rank.eq(7)))),
          expected((d) => d.data.rank == 7),
        );
      });

      test('findAndCount returns the page and the total', () async {
        final r = await items
            .where((f) => f.rank.lt(25))
            .orderBy((f) => f.name.asc)
            .limit(10)
            .findAndCount();
        expect(r.docs, hasLength(10));
        expect(r.count, s.docs.where((d) => d.data.rank < 25).length);
      });

      test('get finds an id with includes, within the where only', () async {
        final doc = s.docs[5];
        final got = await items.query().include((f) => f.owner).get(doc.id);
        expect(got.data.owner.loaded!.id, doc.data.owner.id);
        await expectLater(
          items.where((f) => f.rank.ne(doc.data.rank)).get(doc.id),
          throwsA(isA<ObjectNotFound>()),
        );
      });

      test('includeAll loads every pointer', () async {
        final doc = s.docs.firstWhere((d) => d.data.helpers.isNotEmpty);
        final got = await items.query().includeAll().get(doc.id);
        expect(got.data.owner.loaded, isNotNull);
        expect(got.data.helpers.map((p) => p.loaded), everyElement(isNotNull));
      });

      test('hint, comment and readPreference', () async {
        final q = items.where((f) => f.rank.eq(7));
        final want = expected((d) => d.data.rank == 7);
        expect(ids(await all(q.hint('_id_'))), want);
        expect(ids(await all(q.comment('parity check'))), want);
        expect(
          ids(await all(q.readPreference(ReadPreference.secondaryPreferred))),
          want,
        );
        if (!backend.isPostgres) {
          await expectLater(
            all(q.hint('no_such_index')),
            throwsA(isA<ParseException>()),
          );
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
    });

    group('fullText', () {
      setUpAll(() async {
        await resetItems(backend);
        await inBatches(generate(Random(1), 20, people), items.create);
      });

      test(
        'several words with options, sorted by score',
        skip: backend.isPostgres
            ? 'Postgres passes the search to to_tsquery, where a space is a '
                  'syntax error, and rejects \$caseSensitive '
                  '(PostgresStorageAdapter.js)'
            : null,
        () async {
          final got = await items
              .where(
                (f) => f.note.fullText(
                  'amber birch',
                  language: 'english',
                  caseSensitive: false,
                  diacriticSensitive: false,
                ),
              )
              .orderByTextScore()
              .find();
          int words(Doc<Item> d) =>
              ['amber', 'birch'].where(d.data.note!.contains).length;
          expect(got, isNotEmpty);
          expect(got.map(words), everyElement(greaterThan(0)));
          final scores = got.map(words).toList();
          expect(scores, [...scores]..sort((a, b) => b.compareTo(a)));
        },
      );
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
