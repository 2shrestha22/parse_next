/// The generator reads only the named parameters of the unnamed constructor,
/// generative or factory, and the getters of the same names.
final class ParseClass {
  const ParseClass(this.name);

  /// The server's class name, with the underscore for built-in classes such
  /// as `_User`.
  final String name;
}

/// Read only on constructor parameters, not on fields.
final class ParseKey {
  const ParseKey(this.name);

  final String name;
}
