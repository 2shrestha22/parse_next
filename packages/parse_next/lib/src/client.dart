import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'codec.dart';
import 'exception.dart';

part 'auth.dart';
part 'batch.dart';
part 'collection.dart';
part 'live.dart';
part 'query.dart';
part 'schema.dart';

final class ParseClient {
  /// [server] is the mount point, such as `https://example.com/parse`.
  ///
  /// [close] closes [httpClient] only when this client created it.
  ///
  /// [sessions] is read once, on the first request or [Auth] call; values
  /// written to it afterwards by anything else are not seen. Every request
  /// carries the session token while one exists. Without a store, the
  /// session lasts as long as this client. When a write to [sessions] fails,
  /// the error is thrown and the new session is kept in memory.
  ParseClient({
    required this.server,
    required this.appId,
    this.clientKey,
    this.masterKey,
    this.installationId,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    this.attempts = 1,
    this.idempotency = false,
    SessionStore? sessions,
    Uri? liveQueryServer,
  }) : liveQueryServer =
           liveQueryServer ??
           server.replace(scheme: server.scheme == 'https' ? 'wss' : 'ws'),
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _sessions = sessions ?? InMemorySessionStore();

  final Uri server;
  final String appId;

  /// Sent as `X-Parse-Client-Key` when set.
  final String? clientKey;

  /// Sent as `X-Parse-Master-Key` on every request and on the live query
  /// connection. Requests then bypass ACLs and class-level permissions and
  /// act as no user; the session token is ignored. Not for code that ships
  /// in an app. Also takes a `readOnlyMasterKey`.
  ///
  /// The server accepts it only from addresses in its `masterKeyIps`,
  /// localhost by default, and answers others with [Unauthorized]. A
  /// LiveQuery server accepts it only when its `keyPairs` list `masterKey`.
  final String? masterKey;

  /// Sent as `X-Parse-Installation-Id`. One per install, kept across runs;
  /// without it every login adds a session. In a browser, requests fail
  /// unless the server's `allowHeaders` lists the header.
  final String? installationId;

  /// Per attempt, from sending to the last byte of the body.
  final Duration timeout;

  /// How many times a read is tried. With more than 1, a read is retried
  /// after a [NetworkError] or a 502, 503 or 504, with a random exponential
  /// backoff. A write is retried only with [idempotency].
  final int attempts;

  /// Sends each create and update with an `X-Parse-Request-Id`, repeated on
  /// its retries, and retries it like a read. A server whose
  /// `idempotencyOptions` cover the route applies it once and answers a
  /// repeat with 159; without that option a retried write can apply twice.
  final bool idempotency;

  /// Where [Query.live] connects. Defaults to [server] with the scheme `ws`
  /// or `wss`.
  final Uri liveQueryServer;

  final http.Client _http;
  final bool _ownsHttp;
  final SessionStore _sessions;
  _Session? _current;
  bool _loaded = false;
  Future<void>? _loading;
  final _changes = StreamController<_Session?>.broadcast();
  late final _live = _LiveSocket(this);

  Collection<T, F, O> collection<T, F, O>(ParseSchema<T, F, O> schema) =>
      Collection._(this, schema);

  /// [schema] is the app's `@ParseClass('_User')` model.
  Auth<U> auth<U>(ParseSchema<U, Object?, Object?> schema) =>
      Auth._(this, schema);

  /// Calls the cloud function [name]. The response holds its return value
  /// under `result`, absent when it returned `undefined`.
  Future<Json> callFunction(String name, Json params) =>
      request(this, 'POST', '/functions/$name', body: params);

  /// The config params. Without [masterKey], params marked `masterKeyOnly`
  /// are left out.
  Future<Json> config() async =>
      (await request(this, 'GET', '/config')).require<Json>('params');

  /// Merges [params] into the config, encoded as [encodeValue] does. Each
  /// param in [params] is master-only if it is in [masterKeyOnly] and not
  /// otherwise; other params are unchanged. Needs [masterKey].
  Future<void> saveConfig(
    Map<String, Object?> params, {
    Set<String> masterKeyOnly = const {},
  }) async {
    await request(
      this,
      'PUT',
      '/config',
      body: Json({
        'params': encodeValue(params),
        'masterKeyOnly': {for (final k in masterKeyOnly) k: true},
      }),
    );
  }

  /// Starts the cloud job [name] and returns the id of its `_JobStatus`
  /// object without waiting for the job. Its `status` is `running`, then
  /// `succeeded` or `failed`. Needs [masterKey].
  Future<String> startJob(String name, [Json params = const Json({})]) async {
    final headers = <String, String>{};
    await request(
      this,
      'POST',
      '/jobs/${Uri.encodeComponent(name)}',
      body: params,
      responseHeaders: headers,
    );
    return headers['x-parse-job-status-id']!;
  }

  /// Sends [data], such as `{'alert': 'Hi'}`, to the installations
  /// subscribed to any of [channels] or matched by [where]; give one of the
  /// two. Returns the id of the `_PushStatus` object, before the push is
  /// sent. Throws [ArgumentError] when [where] is not on `_Installation`.
  /// Needs [masterKey] and a push adapter on the server.
  Future<String> push(
    Map<String, Object?> data, {
    List<String>? channels,
    Query<Object?, Object?, Object?>? where,
  }) async {
    final Object? condition;
    if (where == null) {
      condition = null;
    } else {
      final sub = where._subquery();
      if (sub['className'] != '_Installation') {
        throw ArgumentError.value(where, 'where', 'must be on _Installation');
      }
      condition = sub['where'];
    }
    final headers = <String, String>{};
    await request(
      this,
      'POST',
      '/push',
      body: Json({
        'data': encodeValue(data),
        'channels': ?channels,
        'where': ?condition,
      }),
      responseHeaders: headers,
    );
    return headers['x-parse-push-status-id']!;
  }

  /// Every class's schema, in the shape [Schema.get] returns. Needs
  /// [masterKey].
  Future<List<Json>> schemas() async =>
      (await request(this, 'GET', '/schemas')).requireList<Json>('results');

  /// The schema of [className].
  Schema schema(String className) => Schema._(this, className);

  /// Uploads [bytes] with the stored session. Without a session, the server
  /// rejects it with 130 unless `fileUpload.enableForPublic` is set.
  ///
  /// Returns the file under its stored name, which a File field must hold:
  /// [name] with a random hex prefix, and the extension of [contentType]
  /// when [name] has none. A [name] outside `[_a-zA-Z0-9][a-zA-Z0-9@. ~_-]*`,
  /// or longer than 128 characters, fails with 122.
  ///
  /// Downloads are served with the content type of the stored name's
  /// extension, not [contentType]; an unknown extension is served as
  /// `Content-Type: false`. File URLs use the server's `publicServerURL` when
  /// set, else the request host.
  ///
  /// [metadata] and [tags] reach a `beforeSave(Parse.File)` trigger and the
  /// files adapter. [onProgress] is called as bytes are sent; completing
  /// [cancel] aborts the upload with a [NetworkError]. Never retried.
  Future<ParseFile> uploadFile(
    Uint8List bytes, {
    required String name,
    required String contentType,
    Map<String, String>? metadata,
    Map<String, String>? tags,
    void Function(int sent, int total)? onProgress,
    Future<void>? cancel,
  }) async {
    final streamed = metadata != null || tags != null;
    final response = Json(
      await _request<Map<String, Object?>>(
        this,
        'POST',
        '/files/${Uri.encodeComponent(name)}',
        raw: (
          bytes: bytes,
          contentType: contentType,
          onProgress: onProgress,
          cancel: cancel,
          // Only a streamed upload reads metadata and tags, from these
          // headers (`createHandler` in FilesRouter.js).
          headers: {
            if (streamed) 'X-Parse-Upload-Mode': 'stream',
            if (metadata != null) 'X-Parse-File-Metadata': jsonEncode(metadata),
            if (tags != null) 'X-Parse-File-Tags': jsonEncode(tags),
          },
        ),
      ),
    );
    return ParseFile(
      name: response.require<String>('name'),
      url: response.require<String>('url'),
    );
  }

  /// The bytes of [file], fetched from its URL without Parse headers.
  /// Throws [OtherParseError] for any status but 200.
  Future<Uint8List> downloadFile(ParseFile file) async {
    final response = await _send(
      this,
      (abort) => http.AbortableRequest(
        'GET',
        Uri.parse(file.url),
        abortTrigger: abort,
      ),
      null,
    );
    if (response.statusCode != 200) {
      throw OtherParseError(
        'GET ${file.url}: HTTP ${response.statusCode}',
        code: null,
        status: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  /// Removes [file] from storage; fields that hold it are not changed.
  /// Needs [masterKey].
  Future<void> deleteFile(ParseFile file) async {
    await request(
      this,
      'DELETE',
      '/files/${Uri.encodeComponent(file.name)}',
      empty: true,
    );
  }

  /// A batch of writes. Items run concurrently on the server, in no set
  /// order, and each succeeds or fails on its own unless sent with
  /// `send(transaction: true)`.
  Batch batch() => Batch._(this);

  String get _mount => server.path.endsWith('/')
      ? server.path.substring(0, server.path.length - 1)
      : server.path;

  /// Closes the live query socket, ends every [Query.live] stream, and
  /// closes the HTTP client if this client created it.
  void close() {
    _live.close();
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

  /// Clears the session only while [token] is the stored one, so a 209 for a
  /// token given to `become`, or one already logged out, leaves it alone.
  Future<void> _invalidate(String token) async {
    await _session();
    if (_current?.token == token) await _setSession(null);
  }
}

/// [path] starts with `/` and is relative to [ParseClient.server].
///
/// Sends [sessionToken], or the stored session's when it is null and
/// [stored] is true. [context] reaches the triggers the request runs as
/// `request.context`. [responseHeaders], when given, receives the
/// response's headers, with lowercase names. With [empty], a 2xx without a
/// body returns an empty object.
Future<Json> request(
  ParseClient client,
  String method,
  String path, {
  Map<String, String>? query,
  Json? body,
  String? sessionToken,
  bool stored = true,
  Map<String, Object?>? context,
  Map<String, String>? responseHeaders,
  bool empty = false,
}) async => Json(
  await _request<Map<String, Object?>>(
    client,
    method,
    path,
    query: query,
    body: body,
    sessionToken: sessionToken,
    stored: stored,
    context: context,
    responseHeaders: responseHeaders,
    empty: empty,
  ),
);

Future<T> _request<T extends Object>(
  ParseClient client,
  String method,
  String path, {
  Map<String, String>? query,
  Json? body,
  _Raw? raw,
  String? sessionToken,
  bool stored = true,
  bool persistent = true,
  Map<String, Object?>? context,
  Map<String, String>? responseHeaders,
  bool empty = false,
}) async {
  if (sessionToken == null && stored) {
    sessionToken = (await client._session())?.token;
  }
  final Uint8List? json;
  if (body != null) {
    _checkNumbers(body, 'body');
    json = utf8.encode(jsonEncode(body));
  } else {
    json = null;
  }
  final read = method == 'GET' || body?['_method'] == 'GET';
  final idempotent =
      !read &&
      raw == null &&
      client.idempotency &&
      (method == 'POST' || method == 'PUT');
  final requestId = idempotent ? _randomId() : null;

  http.BaseRequest build(Future<void> abort) {
    final url = client.server.replace(
      path: '${client._mount}$path',
      queryParameters: query,
    );
    final http.BaseRequest req;
    if (raw != null) {
      req = _Upload(method, url, raw, abort)
        ..headers.addAll(raw.headers)
        ..headers['Content-Type'] = raw.contentType;
    } else {
      req = http.AbortableRequest(method, url, abortTrigger: abort);
      if (json != null) {
        // Through bodyBytes: the `body` setter appends `; charset=utf-8`.
        (req as http.Request).bodyBytes = json;
        req.headers['Content-Type'] = 'application/json';
      }
    }
    req.persistentConnection = persistent;
    req.headers['X-Parse-Application-Id'] = client.appId;
    // Not `parse-next0.3.0`: the server parses letters followed by digits as
    // an SDK it knows, and for an unknown one leaves out the `Delete` of a
    // field a trigger unset (`supportsForwardDelete` in ClientSDK.js).
    req.headers['X-Parse-Client-Version'] = 'parse-next/$_packageVersion';
    if (client.clientKey case final key?) {
      req.headers['X-Parse-Client-Key'] = key;
    }
    if (client.masterKey case final key?) {
      req.headers['X-Parse-Master-Key'] = key;
    }
    if (client.installationId case final id?) {
      req.headers['X-Parse-Installation-Id'] = id;
    }
    if (sessionToken != null) {
      req.headers['X-Parse-Session-Token'] = sessionToken;
    }
    if (requestId != null) req.headers['X-Parse-Request-Id'] = requestId;
    if (context != null) {
      // A header, not `_context` in the body: the server reads that only
      // from a request that carries its app id in the body too
      // (middlewares.js).
      req.headers['X-Parse-Cloud-Context'] = jsonEncode(encodeValue(context));
    }
    return req;
  }

  for (var attempt = 1; ; attempt++) {
    final retry = (read || idempotent) && attempt < client.attempts;
    final http.Response response;
    try {
      response = await _send(client, build, raw?.cancel);
    } on NetworkError catch (e) {
      if (!retry || e.message == _cancelled) rethrow;
      await _backoff(attempt);
      continue;
    }
    if (retry && const {502, 503, 504}.contains(response.statusCode)) {
      await _backoff(attempt);
      continue;
    }
    responseHeaders?.addAll(response.headers);
    return _decode<T>(client, response, sessionToken, path, empty: empty);
  }
}

typedef _Raw = ({
  Uint8List bytes,
  String contentType,
  void Function(int sent, int total)? onProgress,
  Future<void>? cancel,
  Map<String, String> headers,
});

/// Sent as `X-Parse-Client-Version`; kept equal to the pubspec version by a
/// test.
const _packageVersion = '0.3.0';

const _cancelled = 'cancelled';

/// A random delay up to 125 ms × 2^[attempt].
Future<void> _backoff(int attempt) => Future.delayed(
  Duration(milliseconds: Random().nextInt(125 * (1 << attempt) + 1)),
);

String _randomId() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

Future<http.Response> _send(
  ParseClient client,
  http.BaseRequest Function(Future<void> abort) build,
  Future<void>? cancel,
) async {
  final timedOut = Completer<void>();
  final timer = Timer(client.timeout, timedOut.complete);
  var cancelled = false;
  final abort = Future.any([
    timedOut.future,
    if (cancel != null) cancel.then((_) => cancelled = true),
  ]);
  try {
    // The abort frees the connection on IOClient and BrowserClient; the
    // timeout still covers clients that ignore abortTrigger, like MockClient.
    return await client._http
        .send(build(abort))
        .then(http.Response.fromStream)
        .timeout(client.timeout);
  } on http.RequestAbortedException {
    throw NetworkError(
      cancelled ? _cancelled : 'no response within ${client.timeout}',
    );
  } on http.ClientException catch (e) {
    throw NetworkError(e.message);
  } on TimeoutException {
    throw NetworkError('no response within ${client.timeout}');
  } finally {
    timer.cancel();
  }
}

/// Sends its bytes in chunks as the connection takes them, so that
/// [_Raw.onProgress] follows what was sent.
final class _Upload extends http.BaseRequest implements http.Abortable {
  _Upload(super.method, super.url, this._raw, this.abortTrigger) {
    contentLength = _raw.bytes.length;
  }

  final _Raw _raw;

  @override
  final Future<void> abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    const size = 64 * 1024;
    final total = _raw.bytes.length;
    for (var start = 0; start < total; start += size) {
      final end = min(start + size, total);
      yield Uint8List.sublistView(_raw.bytes, start, end);
      _raw.onProgress?.call(end, total);
    }
  }
}

Future<T> _decode<T extends Object>(
  ParseClient client,
  http.Response response,
  String? sessionToken,
  String path, {
  bool empty = false,
}) async {
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
    if (empty && response.bodyBytes.isEmpty) decoded = <String, Object?>{};
    if (decoded is T) return decoded;
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
  throw _exception(code, message, status, path);
}

/// On the web every number is a double already, so an int is never larger.
const _web = identical(0, 0.0);
const _maxSafeInt = 9007199254740991;

/// Throws [ArgumentError] for NaN and infinity, which JSON cannot hold, and
/// for an int past 2^53, which the server would store rounded.
void _checkNumbers(Object? v, String path) {
  switch (v) {
    case double() when !v.isFinite:
      throw ArgumentError.value(v, path, 'cannot be sent as JSON');
    case int() when !_web && (v > _maxSafeInt || v < -_maxSafeInt):
      throw ArgumentError.value(v, path, 'is past 2^53 and would be rounded');
    case Map<String, Object?>():
      for (final MapEntry(:key, :value) in v.entries) {
        _checkNumbers(value, '$path.$key');
      }
    case List<Object?>():
      for (var i = 0; i < v.length; i++) {
        _checkNumbers(v[i], '$path[$i]');
      }
  }
}

int _statusOf(int? code) => switch (code) {
  1 => 500,
  101 => 404,
  _ => 400,
};

ParseException _exception(int? code, String message, int status, String path) =>
    switch (code) {
      101 when path == '/login' || path == '/verifyPassword' =>
        InvalidCredentials(message, status: status),
      101 => ObjectNotFound(message, status: status),
      137 => DuplicateValue(message, status: status),
      141 => ScriptFailed(message, status: status),
      202 => UsernameTaken(message, status: status),
      203 => EmailTaken(message, status: status),
      209 => InvalidSession(message, status: status),
      null when status == 403 => Unauthorized(message, status: status),
      _ => OtherParseError(message, code: code, status: status),
    };
