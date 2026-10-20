sealed class ParseException implements Exception {
  const ParseException();
}

/// A server value did not match the shape the model expects.
final class DecodeError extends ParseException {
  const DecodeError(this.key, this.message);

  /// Path to the offending value, such as `author.name` or `tags[2]`.
  final String key;
  final String message;

  @override
  String toString() => 'DecodeError: $key: $message';
}
