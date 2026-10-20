import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_smoke/signal.dart';
import 'package:flutter_smoke/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:parse_next/parse_next.dart';

const appId = 'parse-next-it';
const masterKey = 'parse-next-it-master';

// The Android emulator reaches the host's loopback at 10.0.2.2.
final server = Uri.parse(
  'http://${Platform.isAndroid ? '10.0.2.2' : 'localhost'}:1337/parse',
);

/// Clients may not create classes, and only `Signal` is in the server's
/// `liveQuery.classNames`.
Future<void> ensureSignalClass() async {
  final response = await http.post(
    server.replace(path: '${server.path}/schemas/Signal'),
    headers: {
      'X-Parse-Application-Id': appId,
      'X-Parse-Master-Key': masterKey,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'className': 'Signal',
      'fields': {
        'name': {'type': 'String'},
        'points': {'type': 'Number'},
      },
    }),
  );
  final exists = response.body.contains('"code":103');
  if (response.statusCode != 200 && !exists) {
    throw StateError('${response.statusCode} ${response.body}');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign up, CRUD, query, op, live, log out', (tester) async {
    await ensureSignalClass();
    final client = ParseClient(server: server, appId: appId);
    addTearDown(client.close);
    final auth = client.auth(const $UserSchema());
    final signals = client.collection(const $SignalSchema());
    final name = 'smoke-${DateTime.now().microsecondsSinceEpoch}';

    final user = await auth.signUp(
      password: 'pw',
      user: User(username: name),
    );
    expect((await auth.current())!.id, user.id);

    final created = await signals.create(Signal(name: name, points: 1));
    final found = await signals.where((f) => f.name.eq(name)).find();
    expect([for (final d in found) d.id], [created.id]);

    await signals.update(created.id, (o) => [o.points.increment(2)]);
    expect((await signals.get(created.id)).data.points, 3);

    final live = '$name-live';
    final events = StreamIterator(signals.where((f) => f.name.eq(live)).live());
    expect(await events.moveNext(), isTrue);
    expect(events.current, isA<Subscribed<Signal>>());
    final later = await signals.create(Signal(name: live, points: 0));
    expect(
      await events.moveNext().timeout(const Duration(seconds: 20)),
      isTrue,
    );
    expect(
      events.current,
      isA<Created<Signal>>().having((e) => e.doc.id, 'id', later.id),
    );
    await events.cancel();

    await auth.logOut();
    expect(await auth.current(), isNull);
  });
}
