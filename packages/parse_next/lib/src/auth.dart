part of 'client.dart';

/// Where [ParseClient] keeps the session between runs, such as secure
/// storage on a device. The value is opaque; store and return it unchanged.
abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

final class InMemorySessionStore implements SessionStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async => _value = value;

  @override
  Future<void> clear() async => _value = null;
}

final class _Session {
  const _Session(this.token, this.user);

  /// The token is taken out of [response], so it never reaches a model.
  factory _Session.from(Json response) => _Session(
    response.require<String>('sessionToken'),
    Json({...response}..remove('sessionToken')),
  );

  factory _Session.parse(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException catch (e) {
      throw DecodeError('session', 'stored value is not JSON: ${e.message}');
    }
    if (json is! Map<String, Object?>) {
      throw const DecodeError('session', 'stored value is not a JSON object');
    }
    final j = Json(json);
    return _Session(j.require<String>('sessionToken'), j.require<Json>('user'));
  }

  final String token;

  /// The user object as the server last returned it.
  final Json user;

  String encode() => jsonEncode({'sessionToken': token, 'user': user});
}

/// Sign-up, login and the current user, for the `_User` model [U].
///
/// Sign-up, login, become and password reset never send the stored token:
/// a revoked one would fail sign-up and password reset with 209 (only
/// `/login` drops it, in `handleParseHeaders` in middlewares.js).
///
/// Sessions are always revocable, so `X-Parse-Revocable-Session` is not
/// sent: parse-server ignores it and returns `r:` tokens from every route.
final class Auth<U> {
  Auth._(this._client, this._schema);

  final ParseClient _client;
  final ParseSchema<U, Object?, Object?> _schema;

  /// Emits the user on [signUp], [logIn], [logInWith] and [become], and null
  /// on [logOut] and when a request finds the stored session invalid. [me]
  /// does not emit.
  Stream<Doc<U>?> get changes => _client._changes.stream.map(_doc);

  /// The stored user, without a request; null when logged out.
  Future<Doc<U>?> current() async => _doc(await _client._session());

  /// The returned [Doc] has no [Doc.acl], since the response carries none;
  /// [me] fetches it.
  Future<Doc<U>> signUp({required String password, required U user}) async {
    final fields = _withoutNulls(_schema.encode(user));
    final response = await request(
      _client,
      'POST',
      '/users',
      body: Json({...fields, 'password': password}),
      stored: false,
    );
    return _start(_created(fields, response));
  }

  /// Throws [InvalidCredentials] when no user has this [username] and
  /// [password].
  Future<Doc<U>> logIn(String username, String password) async => _start(
    await request(
      _client,
      'POST',
      '/login',
      body: Json({'username': username, 'password': password}),
      stored: false,
    ),
  );

  /// Logs in the user linked to [authData] for [provider], or signs up a new
  /// one. The server validates [authData] with that provider's auth adapter.
  ///
  /// Never sends the stored token: with a session, the server links
  /// [authData] to that user instead of logging in (`handleAuthData` in
  /// RestWrite.js). Throws [InvalidCredentials] when the adapter rejects
  /// [authData] with 101, as parse-server's built-in adapters do, and
  /// [OtherParseError] 252 for a provider the server does not have.
  ///
  /// For a new user the returned [Doc] has no [Doc.acl], as from [signUp].
  Future<Doc<U>> logInWith(
    String provider,
    Map<String, Object?> authData,
  ) async {
    final Json response;
    try {
      response = await request(
        _client,
        'POST',
        '/users',
        body: Json({
          'authData': {provider: authData},
        }),
        stored: false,
      );
    } on ObjectNotFound catch (e) {
      throw InvalidCredentials(e.message, status: e.status);
    }
    // A new user's 201 response, like sign-up's, has no updatedAt.
    return _start(
      response.containsKey('updatedAt')
          ? response
          : _created(Json({}), response),
    );
  }

  /// Adopts a session created elsewhere, such as by cloud code.
  Future<Doc<U>> become(String sessionToken) async => _start(
    await request(_client, 'GET', '/users/me', sessionToken: sessionToken),
  );

  /// The local session is cleared even when the request then fails, and the
  /// failure, such as [NetworkError] or [InvalidSession], is still thrown.
  Future<void> logOut() async {
    String? token;
    try {
      token = (await _client._session())?.token;
    } finally {
      await _client._setSession(null);
    }
    if (token != null) {
      await request(_client, 'POST', '/logout', sessionToken: token);
    }
  }

  /// Succeeds for an unknown [email] too: parse-server answers alike unless
  /// `passwordPolicy.resetPasswordSuccessOnInvalidEmail` is false. Needs an
  /// email adapter, `appName` and `publicServerURL` on the server.
  Future<void> requestPasswordReset(String email) async {
    await request(
      _client,
      'POST',
      '/requestPasswordReset',
      body: Json({'email': email}),
      stored: false,
    );
  }

  /// Fetches the stored session's user and keeps it for [current].
  Future<Doc<U>> me() async {
    final session = _Session.from(await request(_client, 'GET', '/users/me'));
    final doc = _doc(session)!;
    // A logOut or logIn while this was in flight wins.
    if (_client._current?.token == session.token) {
      await _client._setSession(session, emit: false);
    }
    return doc;
  }

  Future<Doc<U>> _start(Json response) async {
    final session = _Session.from(response);
    final doc = _doc(session)!;
    await _client._setSession(session);
    return doc;
  }

  Doc<U>? _doc(_Session? session) =>
      session == null ? null : Doc.decode(session.user, _schema);
}
