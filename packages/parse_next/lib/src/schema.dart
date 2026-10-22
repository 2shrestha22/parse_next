part of 'client.dart';

/// A class's schema, from [ParseClient.schema]. Every call needs
/// [ParseClient.masterKey].
///
/// A field is given as the server writes it, such as `{'type': 'String'}`,
/// `{'type': 'Pointer', 'targetClass': '_User'}` or
/// `{'type': 'Number', 'required': true, 'defaultValue': 0}`; an index as
/// its keys, such as `{'title': 1}`.
final class Schema {
  Schema._(this._client, this.className);

  final ParseClient _client;
  final String className;

  String get _path => '/schemas/${Uri.encodeComponent(className)}';

  /// `className`, `fields`, `classLevelPermissions` and, when there are
  /// any, `indexes`. Throws [OtherParseError] 103 when the class does not
  /// exist.
  Future<Json> get() => request(_client, 'GET', _path);

  /// Fails with 103 when the class exists.
  Future<Json> create({
    Map<String, Map<String, Object?>> fields = const {},
    Map<String, Map<String, Object?>> indexes = const {},
    Map<String, Object?>? classLevelPermissions,
  }) => request(
    _client,
    'POST',
    _path,
    body: Json({
      'className': className,
      'fields': fields,
      if (indexes.isNotEmpty) 'indexes': indexes,
      'classLevelPermissions': ?classLevelPermissions,
    }),
  );

  /// A null in [fields] or [indexes] deletes that field, with its values in
  /// every object, or that index. A field cannot change type: delete it and
  /// add it in a second call. [classLevelPermissions] replaces the class's.
  Future<Json> update({
    Map<String, Map<String, Object?>?> fields = const {},
    Map<String, Map<String, Object?>?> indexes = const {},
    Map<String, Object?>? classLevelPermissions,
  }) => request(
    _client,
    'PUT',
    _path,
    body: Json({
      'className': className,
      'fields': _orDelete(fields),
      if (indexes.isNotEmpty) 'indexes': _orDelete(indexes),
      'classLevelPermissions': ?classLevelPermissions,
    }),
  );

  /// Fails with 255 while the class has objects: [purge] it first.
  Future<void> delete() async {
    await request(_client, 'DELETE', _path);
  }

  /// Deletes every object of the class without running triggers, and keeps
  /// the schema.
  Future<void> purge() async {
    await request(
      _client,
      'DELETE',
      '/purge/${Uri.encodeComponent(className)}',
    );
  }

  static Map<String, Object?> _orDelete(Map<String, Object?> m) => {
    for (final MapEntry(:key, :value) in m.entries)
      key: value ?? const {'__op': 'Delete'},
  };
}
