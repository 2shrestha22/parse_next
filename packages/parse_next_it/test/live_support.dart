import 'dart:async';

import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/signal.dart';
import 'package:test/test.dart';

import 'support.dart';

const signals = $SignalSchema();

Future<void> resetSignals(Backend backend) => backend.resetClass('Signal', {
  'name': {'type': 'String'},
  'points': {'type': 'Number'},
  'label': {'type': 'String'},
  'tags': {'type': 'Array'},
  'at': {'type': 'Date'},
  'place': {'type': 'GeoPoint'},
  'links': {'type': 'Array'},
});

String unique(String name) => '$name-${DateTime.now().microsecondsSinceEpoch}';

String? idOf(LiveEvent<Signal> e) => switch (e) {
  Created(:final doc) ||
  Entered(:final doc) ||
  Updated(:final doc) ||
  Left(:final doc) ||
  Deleted(:final doc) => doc.id,
  Subscribed() => null,
};

/// Everything a live stream emits, kept for later checks.
final class Watch {
  Watch(Stream<LiveEvent<Signal>> stream) {
    _sub = stream.listen(
      events.add,
      onError: errors.add,
      onDone: () => done = true,
    );
    addTearDown(cancel);
  }

  late final StreamSubscription<LiveEvent<Signal>> _sub;
  final events = <LiveEvent<Signal>>[];
  final errors = <Object>[];
  var done = false;

  List<LiveEvent<Signal>> about(String id) => [
    for (final e in events)
      if (idOf(e) == id) e,
  ];

  Future<void> cancel() => _sub.cancel();

  int get subscribed => events.whereType<Subscribed<Signal>>().length;

  /// The server registers a subscription before confirming it, so a write
  /// after the [Subscribed] that this waits for is always seen.
  Future<void> confirmed([int times = 1]) => until(
    () => subscribed >= times || done,
    timeout: const Duration(minutes: 2),
    reason: 'Subscribed #$times',
  );
}

Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$reason not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
