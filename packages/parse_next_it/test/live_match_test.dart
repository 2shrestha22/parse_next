@Tags(['live'])
library;

import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/signal.dart';
import 'package:test/test.dart';

import 'live_support.dart';
import 'support.dart';

final d1 = DateTime.utc(2024);
final d2 = DateTime.utc(2024, 6);
final d3 = DateTime.utc(2025);

List<Signal> fixtures(String name) => [
  Signal(
    name: name,
    points: 5,
    label: 'apple',
    tags: const ['x'],
    at: d1,
    place: GeoPoint(10, 10),
  ),
  Signal(
    name: name,
    points: 20,
    label: 'Avocado',
    tags: const ['x', 'y'],
    at: d2,
    place: GeoPoint(20, 20),
  ),
  Signal(name: name),
  Signal(
    name: name,
    points: 1,
    label: 'und',
    tags: const ['y'],
    at: d3,
    place: GeoPoint(-10, -10),
  ),
  Signal(
    name: name,
    points: 10,
    label: 'banana',
    tags: const [],
    at: d1,
    place: GeoPoint(15, 15),
  ),
  Signal(name: name, points: 30),
];

void main() {
  forEachBackend((backend) {
    setUpAll(() => resetSignals(backend));

    for (final (label, Cond<Signal> Function(SignalFields) cond) in [
      ('gt', (f) => f.points.gt(10)),
      ('gte', (f) => f.points.gte(10)),
      ('lt', (f) => f.points.lt(10)),
      ('lte', (f) => f.points.lte(10)),
      ('eq', (f) => f.points.eq(20)),
      ('ne', (f) => f.points.ne(20)),
      ('oneOf', (f) => f.points.oneOf([1, 20])),
      ('noneOf', (f) => f.points.noneOf([1, 20])),
      ('exists', (f) => f.points.exists()),
      ('exists false', (f) => f.points.exists(false)),
      ('startsWith und', (f) => f.label.startsWith('und')),
      ('startsWith a', (f) => f.label.startsWith('a')),
      ('matches i', (f) => f.label.matches('^a', caseInsensitive: true)),
      ('contains', (f) => f.tags.contains('x')),
      ('containsAll', (f) => f.tags.containsAll(['x', 'y'])),
      ('date gt', (f) => f.at.gt(d1)),
      ('date lt', (f) => f.at.lt(d3)),
      ('date eq', (f) => f.at.eq(d1)),
      ('near', (f) => f.place.near(GeoPoint(10, 10), maxKm: 1500)),
      ('withinBox', (f) => f.place.withinBox(GeoPoint(0, 0), GeoPoint(18, 18))),
      (
        'withinPolygon',
        (f) => f.place.withinPolygon(
          Polygon([
            GeoPoint(0, 0),
            GeoPoint(0, 18),
            GeoPoint(18, 18),
            GeoPoint(18, 0),
          ]),
        ),
      ),
      ('or', (f) => f.points.gt(10) | f.label.eq('apple')),
    ]) {
      test(
        'live $label matches what find returns',
        skip: switch (label) {
          'noneOf' when backend.isPostgres =>
            r'$nin never matches an absent field on Postgres; live matching '
                'follows Mongo',
          _ => null,
        },
        () async {
          final c = backend.client();
          addTearDown(c.close);
          final live = c.collection(signals);
          final name = unique('match');
          final watch = Watch(
            live.where((f) => f.name.eq(name) & cond(f)).live(),
          );
          await watch.confirmed();

          final created = [
            for (final s in fixtures(name)) (await live.create(s)).id,
          ];
          final expected = {
            for (final d
                in await live.where((f) => f.name.eq(name) & cond(f)).find())
              d.id,
          };
          await until(
            () => watch.events
                .whereType<Created<Signal>>()
                .map((e) => e.doc.id)
                .toSet()
                .containsAll(expected),
            reason: 'expected events',
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect({
            for (final e in watch.events.whereType<Created<Signal>>())
              if (created.contains(e.doc.id)) e.doc.id,
          }, expected);
          expect(watch.errors, isEmpty);
        },
      );
    }
  });
}
