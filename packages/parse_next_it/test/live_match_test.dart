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
    links: const [Pointer('s1')],
  ),
  Signal(
    name: name,
    points: 20,
    label: 'Avocado',
    tags: const ['x', 'y'],
    at: d2,
    place: GeoPoint(20, 20),
    links: const [Pointer('s2'), Pointer('s3')],
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
    links: const [],
  ),
  Signal(name: name, points: 30),
];

void main() {
  forEachBackend((backend) {
    setUpAll(() => resetSignals(backend));

    // Only conditions live() rewrites: the rest match in the server's
    // QueryTools.js as they are sent, which tests the server, not this SDK.
    for (final (label, Cond<Signal> Function(SignalFields) cond) in [
      ('gt', (f) => f.points.gt(10)),
      ('gte', (f) => f.points.gte(10)),
      ('lt', (f) => f.points.lt(10)),
      ('lte', (f) => f.points.lte(10)),
      ('date gt', (f) => f.at.gt(d1)),
      ('date lt', (f) => f.at.lt(d3)),
      ('startsWith und', (f) => f.label.startsWith('und')),
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
      ('containedBy', (f) => f.tags.exists() & f.tags.containedBy(['x'])),
      ('or', (f) => f.points.gt(10) | f.label.eq('apple')),
      ('nor', (f) => ~f.points.gt(10)),
      ('nor of a regex', (f) => ~f.label.startsWith('a')),
      ('an empty oneOf in or', (f) => f.points.oneOf([]) | f.points.gt(10)),
    ]) {
      test(
        'live $label matches what find returns',
        skip: switch (label) {
          'nor' || 'nor of a regex' when backend.isPostgres =>
            r'NOT never matches an absent field on Postgres, as with $nin; '
                'live matching follows Mongo',
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
