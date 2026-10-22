sealed class ParseException implements Exception {
  const ParseException();

  String get message;
}

/// A server value did not match the shape the model expects.
final class DecodeError extends ParseException {
  const DecodeError(this.key, this.message, {this.id});

  /// Path to the offending value, such as `author.name` or `tags[2]`.
  final String key;
  @override
  final String message;

  /// The `objectId` of the row that failed, from `Query.tryFind`; null
  /// elsewhere and when the row has no string `objectId`.
  final String? id;

  @override
  String toString() =>
      'DecodeError: ${id == null ? '' : '$id: '}$key: $message';
}

/// The object does not exist, or its ACL hides it from this caller; both
/// are 101.
final class ObjectNotFound extends ParseException {
  const ObjectNotFound(this.message, {required this.status});

  int get code => 101;
  @override
  final String message;
  final int status;

  @override
  String toString() => 'ObjectNotFound ($code, HTTP $status): $message';
}

final class DuplicateValue extends ParseException {
  const DuplicateValue(this.message, {required this.status});

  int get code => 137;
  @override
  final String message;
  final int status;

  @override
  String toString() => 'DuplicateValue ($code, HTTP $status): $message';
}

/// A cloud function or trigger threw; [message] is what it threw.
final class ScriptFailed extends ParseException {
  const ScriptFailed(this.message, {required this.status});

  int get code => 141;
  @override
  final String message;
  final int status;

  @override
  String toString() => 'ScriptFailed ($code, HTTP $status): $message';
}

/// The session token was revoked, expired or never existed. When the
/// request carried the client's stored session, that session is already
/// cleared and `Auth.changes` has emitted null by the time this is thrown.
final class InvalidSession extends ParseException {
  const InvalidSession(this.message, {required this.status});

  int get code => 209;
  @override
  final String message;
  final int status;

  @override
  String toString() => 'InvalidSession ($code, HTTP $status): $message';
}

/// `/login` found no user with that username and password, or the provider
/// rejected the `authData` given to `Auth.logInWith`; both are 101, which
/// elsewhere is [ObjectNotFound].
final class InvalidCredentials extends ParseException {
  const InvalidCredentials(this.message, {required this.status});

  int get code => 101;
  @override
  final String message;
  final int status;

  @override
  String toString() => 'InvalidCredentials ($code, HTTP $status): $message';
}

final class UsernameTaken extends ParseException {
  const UsernameTaken(this.message, {required this.status});

  int get code => 202;
  @override
  final String message;
  final int status;

  @override
  String toString() => 'UsernameTaken ($code, HTTP $status): $message';
}

final class EmailTaken extends ParseException {
  const EmailTaken(this.message, {required this.status});

  int get code => 203;
  @override
  final String message;
  final int status;

  @override
  String toString() => 'EmailTaken ($code, HTTP $status): $message';
}

/// The server rejected the application id or key with a 403 that has no
/// Parse error code.
final class Unauthorized extends ParseException {
  const Unauthorized(this.message, {required this.status});

  @override
  final String message;
  final int status;

  @override
  String toString() => 'Unauthorized (HTTP $status): $message';
}

/// No response arrived: the connection failed or the timeout elapsed.
///
/// The request may still have reached the server, so a write may have been
/// applied.
///
/// Also thrown for the request after a 500 `Internal server error.` on the
/// same connection, which the server closes.
final class NetworkError extends ParseException {
  const NetworkError(this.message);

  @override
  final String message;

  @override
  String toString() => 'NetworkError: $message';
}

/// Any other failed response. [code] is null when the body carried none,
/// including bodies that are not JSON, whose text is then the [message].
final class OtherParseError extends ParseException {
  const OtherParseError(
    this.message, {
    required this.code,
    required this.status,
  });

  final int? code;
  @override
  final String message;
  final int status;

  @override
  String toString() =>
      'OtherParseError (${code ?? 'no code'}, HTTP $status): '
      '$message';
}

/// One outcome of a call that succeeds or fails per item: a batch item or a
/// `Query.tryFind` row.
sealed class Result<R> {
  const Result();
}

final class Ok<R> extends Result<R> {
  const Ok(this.value);

  final R value;
}

final class Err<R> extends Result<R> {
  const Err(this.error);

  final ParseException error;
}
