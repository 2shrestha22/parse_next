part of 'client.dart';

/// One change seen by [Query.live].
sealed class LiveEvent<T> {
  const LiveEvent();
}

/// A new object matches the query.
final class Created<T> extends LiveEvent<T> {
  const Created(this.doc);

  final Doc<T> doc;
}

/// A change made an object match that did not before.
final class Entered<T> extends LiveEvent<T> {
  const Entered(this.doc);

  final Doc<T> doc;
}

/// A matching object changed and still matches.
final class Updated<T> extends LiveEvent<T> {
  const Updated(this.doc);

  final Doc<T> doc;
}

/// A change made a matching object stop matching. [doc] is the object after
/// the change, or before it when the change took away this subscription's
/// read access (`_onAfterSave` in ParseLiveQueryServer.ts).
final class Left<T> extends LiveEvent<T> {
  const Left(this.doc);

  final Doc<T> doc;
}

/// A matching object was deleted; [doc] is its last state.
final class Deleted<T> extends LiveEvent<T> {
  const Deleted(this.doc);

  final Doc<T> doc;
}

/// The server confirmed the subscription: first after listening, then after
/// every reconnect. Changes before a [Subscribed] may be missing and are not
/// replayed, so (re)load the state after each one.
final class Subscribed<T> extends LiveEvent<T> {
  const Subscribed();
}

const _maxBackoff = Duration(seconds: 30);

final class _LiveSocket {
  _LiveSocket(this._client);

  final ParseClient _client;
  final _subs = <int, _LiveSub<Object?>>{};
  var _nextId = 0;
  WebSocketChannel? _channel;
  var _connected = false;
  Timer? _retry;
  var _backoff = const Duration(seconds: 1);
  var _closed = false;

  Stream<LiveEvent<T>> subscribe<T>(
    ParseSchema<T, Object?, Object?> schema,
    Map<String, Object?> where,
  ) {
    late final StreamController<LiveEvent<T>> controller;
    _LiveSub<T>? sub;
    var cancelled = false;
    controller = StreamController(
      onListen: () async {
        final String? token;
        try {
          token = (await _client._session())?.token;
        } on Object catch (e, s) {
          controller
            ..addError(e, s)
            ..close();
          return;
        }
        if (cancelled) return;
        if (_closed) {
          controller.close();
          return;
        }
        final s = sub = _LiveSub(++_nextId, schema, controller, {
          'className': schema.className,
          'where': where,
        }, token);
        _subs[s.id] = s;
        if (_connected) {
          _subscribe(s);
        } else if (_channel == null && _retry == null) {
          _open();
        }
      },
      onCancel: () {
        cancelled = true;
        if (sub case final s?) _remove(s.id);
      },
    );
    return controller.stream;
  }

  void close() {
    _closed = true;
    final subs = [..._subs.values];
    _subs.clear();
    _shutdown();
    for (final s in subs) {
      s.controller.close();
    }
  }

  void _remove(int id) {
    if (_subs.remove(id) == null) return;
    if (_connected) _send({'op': 'unsubscribe', 'requestId': id});
    if (_subs.isEmpty) _shutdown();
  }

  void _shutdown() {
    _retry?.cancel();
    _retry = null;
    final channel = _channel;
    _channel = null;
    _connected = false;
    _backoff = const Duration(seconds: 1);
    channel?.sink.close();
  }

  void _open() {
    final channel = WebSocketChannel.connect(_client.liveQueryServer);
    _channel = channel;
    // A failed connect also ends the stream, which onDone handles.
    channel.ready.ignore();
    channel.stream.listen(
      (message) {
        if (identical(_channel, channel)) _message(message);
      },
      onError: (Object _) {},
      onDone: () {
        if (identical(_channel, channel)) _lost();
      },
    );
    // The sink buffers until the socket is open. No sessionToken here: the
    // server matches every subscribe sent without one against the connect
    // token (`_matchesACL` in ParseLiveQueryServer.ts).
    _send({
      'op': 'connect',
      'applicationId': _client.appId,
      'clientKey': ?_client.clientKey,
    });
  }

  void _lost() {
    _channel = null;
    _connected = false;
    if (_subs.isEmpty) return;
    _retry = Timer(_backoff, () {
      _retry = null;
      _open();
    });
    final doubled = _backoff * 2;
    _backoff = doubled > _maxBackoff ? _maxBackoff : doubled;
  }

  void _send(Map<String, Object?> message) =>
      _channel?.sink.add(jsonEncode(message));

  void _subscribe(_LiveSub<Object?> sub) => _send({
    'op': 'subscribe',
    'requestId': sub.id,
    'query': sub.query,
    'sessionToken': ?sub.token,
  });

  void _message(Object? raw) {
    final Object? message;
    try {
      message = raw is String ? jsonDecode(raw) : null;
    } on FormatException {
      return;
    }
    if (message is! Map<String, Object?>) return;
    final sub = switch (message['requestId']) {
      final num id => _subs[id.toInt()],
      _ => null,
    };
    switch (message['op']) {
      case 'connected':
        _connected = true;
        _backoff = const Duration(seconds: 1);
        _subs.values.forEach(_subscribe);
      case 'subscribed':
        sub?.subscribed();
      case final String op &&
          ('create' || 'enter' || 'update' || 'leave' || 'delete'):
        sub?.event(op, message['object']);
      case 'error':
        final code = switch (message['code']) {
          final num n => n.toInt(),
          _ => null,
        };
        final text = switch (message['error']) {
          final String m => m,
          _ => '',
        };
        if (sub != null) {
          _remove(sub.id);
          sub.fail(_exception(code, text, _statusOf(code), sub.path));
        } else if (!_connected && message['requestId'] == null) {
          // Refused before `connected` (a bad key or a beforeConnect
          // trigger); reconnecting would be refused the same way. After
          // `connected`, errors without a requestId answer an unsubscribe
          // that raced its subscribe.
          final subs = [..._subs.values];
          _subs.clear();
          _shutdown();
          for (final s in subs) {
            s.fail(_exception(code, text, _statusOf(code), s.path));
          }
        }
    }
  }
}

final class _LiveSub<T> {
  _LiveSub(this.id, this.schema, this.controller, this.query, this.token);

  final int id;
  final ParseSchema<T, Object?, Object?> schema;
  final StreamController<LiveEvent<T>> controller;
  final Map<String, Object?> query;
  final String? token;

  String get path => '/classes/${schema.className}';

  void subscribed() => controller.add(Subscribed<T>());

  void event(String op, Object? object) {
    final Doc<T> doc;
    try {
      if (object is! Map<String, Object?>) {
        throw const DecodeError('object', 'expected an object');
      }
      doc = Doc.decode(Json(object), schema);
    } on DecodeError catch (e, s) {
      controller.addError(e, s);
      return;
    }
    controller.add(switch (op) {
      'create' => Created(doc),
      'enter' => Entered(doc),
      'update' => Updated(doc),
      'leave' => Left(doc),
      _ => Deleted(doc),
    });
  }

  void fail(ParseException e) {
    controller.addError(e);
    controller.close();
  }
}

/// Live matching runs in JavaScript on the LiveQuery server, not in the
/// database (`matchesKeyConstraints` in QueryTools.js). Constraints it would
/// silently get wrong are rejected; the rest are adjusted to match as a find
/// does.
Map<String, Object?> _liveWhere(Map<String, Object?> where) => {
  for (final MapEntry(:key, :value) in where.entries)
    key: switch (key) {
      r'$or' || r'$and' => [
        for (final w in value! as List<Object?>)
          _liveWhere(w! as Map<String, Object?>),
      ],
      r'$relatedTo' => _unsupported('RelationField.of never matches'),
      // Sent as ISO strings and compared with a Date: ranges always match
      // and equality never does.
      'createdAt' || 'updatedAt' => _unsupported('$key cannot be matched'),
      _ => _liveConstraint(value),
    },
};

/// Without `$exists` first, an absent field passes every range check
/// (`undefined < x` and `undefined >= x` are both false), a `$regex` is
/// tested against the string "undefined", and `$geoWithin` throws, which
/// drops the event.
const _needsExists = {
  r'$lt',
  r'$lte',
  r'$gt',
  r'$gte',
  r'$regex',
  r'$geoWithin',
};

Object? _liveConstraint(Object? value) {
  if (value is! Map<String, Object?> || value.containsKey('__type')) {
    return value;
  }
  if (value.containsKey(r'$text')) _unsupported('fullText never matches');
  if (value.containsKey(r'$inQuery')) {
    _unsupported('PointerField.matchesQuery never matches');
  }
  if (value[r'$all'] case final List<Object?> all) {
    if (all.isEmpty) _unsupported('an empty containsAll matches every list');
    if (all.any((v) => v is Map)) {
      _unsupported('contains on a pointer list never matches');
    }
  }
  return value.keys.any(_needsExists.contains)
      ? {r'$exists': true, ...value}
      : value;
}

Never _unsupported(String why) =>
    throw ArgumentError('Not supported by live queries: $why.');
