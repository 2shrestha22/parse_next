sealed class ParseException implements Exception {
  const ParseException();

  String get message;
}

/// A server value did not match the shape the model expects.
final class DecodeError extends ParseException {
  const DecodeError(this.key, this.message);

  /// Path to the offending value, such as `author.name` or `tags[2]`.
  final String key;
  @override
  final String message;

  @override
  String toString() => 'DecodeError: $key: $message';
}

/// The object does not exist, or the ACL hides it from this caller: the
/// server answers both with 101.
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

final class InvalidSession extends ParseException {
  const InvalidSession(this.message, {required this.status});

  int get code => 209;
  @override
  final String message;
  final int status;

  @override
  String toString() => 'InvalidSession ($code, HTTP $status): $message';
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
/// applied. The SDK never retries; decide yourself whether repeating the
/// call is safe.
///
/// Also raised for the call right after a 500 `Internal server error.`:
/// parse-server destroys that keep-alive socket after responding
/// (`handleParseErrors` in middlewares.js), so the next request on it fails
/// before reaching the server.
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
