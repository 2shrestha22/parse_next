import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'codec.dart';
import 'exception.dart';

part 'auth.dart';
part 'collection.dart';
part 'query.dart';

final class ParseClient {
  /// [server] is the mount point, such as `https://example.com/parse`.
  ///
  /// An [httpClient] passed here stays owned by the caller, and [close] leaves
  /// it open. Without one, [ParseClient] creates its own and [close] closes it.
  ///
  /// [sessions] is read once, on the first request or [Auth] call, not here;
  /// a value written to it by anything but this client after that is not
  /// seen. Every request then carries the session token while one exists.
  /// Without a store, the session lasts as long as this client. When a write
  /// to [sessions] fails, the error reaches the caller but this client keeps
  /// the new session in memory.
  ParseClient({
    required this.server,
    required this.appId,
    this.clientKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    SessionStore? sessions,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _sessions = sessions ?? InMemorySessionStore();

  final Uri server;
  final String appId;

  /// Sent as `X-Parse-Client-Key` when set.
  final String? clientKey;

  /// Covers the whole request, from sending to the last byte of the body.
  final Duration timeout;

  final http.Client _http;
  final bool _ownsHttp;
  final SessionStore _sessions;
  _Session? _current;
  bool _loaded = false;
  Future<void>? _loading;
  final _changes = StreamController<_Session?>.broadcast();

  Collection<T, F, O> collection<T, F, O>(ParseSchema<T, F, O> schema) =>
      Collection._(this, schema);

  /// [schema] is the app's `@ParseClass('_User')` model.
  Auth<U> auth<U>(ParseSchema<U, Object?, Object?> schema) =>
      Auth._(this, schema);

  void close() {
    _changes.close();
    if (_ownsHttp) _http.close();
  }

  Future<_Session?> _session() async {
    if (!_loaded) {
      final loading = _loading ??= _read();
      try {
        await loading;
      } on Object {
        // A failed read is not kept, so a transient store error is retried.
        if (identical(_loading, loading)) _loading = null;
        rethrow;
      }
    }
    return _current;
  }

  Future<void> _read() async {
    final raw = await _sessions.read();
    // A session set while the read was in flight is newer than the store.
    if (_loaded) return;
    _current = raw == null ? null : _Session.parse(raw);
    _loaded = true;
  }

  /// [_current] changes before the store is awaited, so a second 209
  /// arriving meanwhile already sees the session gone and emits nothing.
  Future<void> _setSession(_Session? session, {bool emit = true}) async {
    _current = session;
    _loaded = true;
    if (emit && !_changes.isClosed) _changes.add(session);
    if (session == null) {
      await _sessions.clear();
    } else {
      await _sessions.write(session.encode());
    }
  }

  /// Only when [token] is still the stored one: a 209 for a token given to
  /// `become`, or one already logged out, leaves the current session alone.
  Future<void> _invalidate(String token) async {
    await _session();
    if (_current?.token == token) await _setSession(null);
  }
}

/// [path] starts with `/` and is relative to [ParseClient.server].
///
/// Sends [sessionToken], or the stored session's when it is null and
/// [stored] is true.
Future<Json> request(
  ParseClient client,
  String method,
  String path, {
  Map<String, String>? query,
  Json? body,
  String? sessionToken,
  bool stored = true,
}) async {
  if (sessionToken == null && stored) {
    sessionToken = (await client._session())?.token;
  }
  final base = client.server.path.endsWith('/')
      ? client.server.path.substring(0, client.server.path.length - 1)
      : client.server.path;
  final timedOut = Completer<void>();
  final timer = Timer(client.timeout, timedOut.complete);
  final req = http.AbortableRequest(
    method,
    client.server.replace(path: '$base$path', queryParameters: query),
    abortTrigger: timedOut.future,
  );
  req.headers['X-Parse-Application-Id'] = client.appId;
  if (client.clientKey case final key?) req.headers['X-Parse-Client-Key'] = key;
  if (sessionToken != null) req.headers['X-Parse-Session-Token'] = sessionToken;
  if (body != null) {
    // Through bodyBytes: the `body` setter appends `; charset=utf-8`.
    req.headers['Content-Type'] = 'application/json';
    req.bodyBytes = utf8.encode(jsonEncode(body));
  }

  final http.Response response;
  try {
    // The abort frees the connection on IOClient and BrowserClient; the
    // timeout still covers clients that ignore abortTrigger, like MockClient.
    response = await client._http
        .send(req)
        .then(http.Response.fromStream)
        .timeout(client.timeout);
  } on http.RequestAbortedException {
    throw NetworkError('no response within ${client.timeout}');
  } on http.ClientException catch (e) {
    throw NetworkError(e.message);
  } on TimeoutException {
    throw NetworkError('no response within ${client.timeout}');
  } finally {
    timer.cancel();
  }

  // Not response.body: without a charset it decodes as latin1, and the
  // unauthorized response has no Content-Type at all (middlewares.js
  // invalidRequest).
  final text = utf8.decode(response.bodyBytes, allowMalformed: true);
  final status = response.statusCode;
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(response.bodyBytes));
  } on FormatException {
    decoded = null;
  }

  if (status >= 200 && status < 300) {
    if (decoded is Map<String, Object?>) return Json(decoded);
    throw OtherParseError(text, code: null, status: status);
  }
  if (decoded is! Map<String, Object?>) {
    throw OtherParseError(text, code: null, status: status);
  }

  final code = switch (decoded['code']) {
    final num n => n.toInt(),
    _ => null,
  };
  // Uncaught server errors put the text under `message`, not `error`
  // (middlewares.js handleParseErrors).
  final message = switch (decoded) {
    {'error': final String m} || {'message': final String m} => m,
    _ => text,
  };
  if (code == 209 && sessionToken != null) {
    await client._invalidate(sessionToken);
  }
  throw switch (code) {
    101 when path == '/login' => InvalidCredentials(message, status: status),
    101 => ObjectNotFound(message, status: status),
    137 => DuplicateValue(message, status: status),
    141 => ScriptFailed(message, status: status),
    202 => UsernameTaken(message, status: status),
    203 => EmailTaken(message, status: status),
    209 => InvalidSession(message, status: status),
    null when status == 403 => Unauthorized(message, status: status),
    _ => OtherParseError(message, code: code, status: status),
  };
}
