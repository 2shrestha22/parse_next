import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'codec.dart';
import 'exception.dart';

final class ParseClient {
  /// [server] is the mount point, such as `https://example.com/parse`.
  ///
  /// An [httpClient] passed here stays owned by the caller, and [close] leaves
  /// it open. Without one, [ParseClient] creates its own and [close] closes it.
  ParseClient({
    required this.server,
    required this.appId,
    this.clientKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  final Uri server;
  final String appId;

  /// Sent as `X-Parse-Client-Key` when set.
  final String? clientKey;

  /// Covers the whole request, from sending to the last byte of the body.
  final Duration timeout;

  final http.Client _http;
  final bool _ownsHttp;

  void close() {
    if (_ownsHttp) _http.close();
  }
}

/// [path] starts with `/` and is relative to [ParseClient.server].
Future<Json> request(
  ParseClient client,
  String method,
  String path, {
  Map<String, String>? query,
  Json? body,
  String? sessionToken,
}) async {
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

  final code = switch (decoded['code']) { final num n => n.toInt(), _ => null };
  // Uncaught server errors put the text under `message`, not `error`
  // (middlewares.js handleParseErrors).
  final message = switch (decoded) {
    {'error': final String m} || {'message': final String m} => m,
    _ => text,
  };
  throw switch (code) {
    101 => ObjectNotFound(message, status: status),
    137 => DuplicateValue(message, status: status),
    141 => ScriptFailed(message, status: status),
    209 => InvalidSession(message, status: status),
    null when status == 403 => Unauthorized(message, status: status),
    _ => OtherParseError(message, code: code, status: status),
  };
}
