part of 'client.dart';

final class Collection<T, O> {
  Collection._(this._client, this._schema);

  final ParseClient _client;
  final ParseSchema<T, O> _schema;

  String get _path => '/classes/${_schema.className}';
  String _object(String id) => '$_path/${Uri.encodeComponent(id)}';

  /// Null fields are left out. The returned [Doc] includes the fields a
  /// `beforeSave` trigger changed, and its [Doc.updatedAt] is
  /// [Doc.createdAt], since the create response carries no `updatedAt`.
  Future<Doc<T>> create(T value, {Acl? acl}) async {
    final body = Json({
      // Not sent as null: on Mongo a stored null Polygon makes every later
      // read of the object a 500 (PolygonCoder in MongoTransform.js).
      for (final MapEntry(:key, value: v) in _schema.encode(value).entries)
        if (v != null) key: v,
      if (acl != null) 'ACL': acl.toJson(),
    });
    final response = await request(_client, 'POST', _path, body: body);
    final stored = {...body, ...response, 'updatedAt': response['createdAt']}
      // A field the trigger unset comes back as a Delete op
      // (`_updateResponseWithData` in parse-server's RestWrite.js).
      ..removeWhere(
          (_, v) => v is Map<String, Object?> && v['__op'] == 'Delete');
    return Doc.decode(Json(stored), _schema);
  }

  Future<Doc<T>> get(String id) async =>
      Doc.decode(await request(_client, 'GET', _object(id)), _schema);

  /// Sends the ops in one request, which the server applies atomically.
  /// Returns the new `updatedAt`.
  Future<DateTime> update(String id, List<Op> Function(O ops) build) async {
    final ops = build(_schema.ops);
    if (ops.isEmpty) throw ArgumentError.value(ops, 'build', 'returned no ops');
    final body = Json({});
    for (final op in ops) {
      if (body.containsKey(op._key)) {
        throw ArgumentError.value(op._key, 'build', 'has two ops on one key');
      }
      body[op._key] = op._json;
    }
    final response = await request(_client, 'PUT', _object(id), body: body);
    return response.require<DateTime>('updatedAt');
  }

  /// Overwrites every field except relations; the ACL changes only when
  /// [acl] is given. Returns the new `updatedAt`.
  Future<DateTime> replace(String id, T value, {Acl? acl}) async {
    final body = Json({
      // A PUT merges into the stored object, so a null must be sent as a
      // Delete or the old value survives.
      for (final MapEntry(:key, value: v) in _schema.encode(value).entries)
        key: v ?? _delete,
      if (acl != null) 'ACL': acl.toJson(),
    });
    final response = await request(_client, 'PUT', _object(id), body: body);
    return response.require<DateTime>('updatedAt');
  }

  Future<void> delete(String id) async {
    await request(_client, 'DELETE', _object(id));
  }
}

/// One field change for [Collection.update], built from a schema's ops.
final class Op {
  const Op._(this._key, this._json);

  final String _key;
  final Object? _json;
}

const _delete = {'__op': 'Delete'};

Object? _same(Object? v) => v;

final class SetOps<V> {
  const SetOps(this._key, [this._encode = _same]);

  final String _key;
  final Object? Function(V) _encode;

  Op set(V value) => Op._(_key, _encode(value));
}

final class NullableSetOps<V> extends SetOps<V> {
  const NullableSetOps(super._key, [super._encode]);

  Op unset() => Op._(_key, _delete);
}

final class NumOps<N extends num> extends SetOps<N> {
  const NumOps(super._key);

  Op increment(N by) => Op._(_key, {'__op': 'Increment', 'amount': by});
}

final class NullableNumOps<N extends num> extends NumOps<N> {
  const NullableNumOps(super._key);

  Op unset() => Op._(_key, _delete);
}

final class ListOps<E> {
  const ListOps(this._key, [this._encode = _same]);

  final String _key;
  final Object? Function(E) _encode;

  Op set(List<E> value) => Op._(_key, _all(value));
  Op add(List<E> values) => _op('Add', values);
  Op addUnique(List<E> values) => _op('AddUnique', values);
  Op remove(List<E> values) => _op('Remove', values);

  List<Object?> _all(List<E> values) => [for (final e in values) _encode(e)];
  Op _op(String op, List<E> values) =>
      Op._(_key, {'__op': op, 'objects': _all(values)});
}

final class NullableListOps<E> extends ListOps<E> {
  const NullableListOps(super._key, [super._encode]);

  Op unset() => Op._(_key, _delete);
}

final class RelationOps<T> {
  const RelationOps(this._key, this._schema);

  final String _key;
  final ParseSchema<T, Object?> _schema;

  Op add(List<Pointer<T>> targets) => _op('AddRelation', targets);
  Op remove(List<Pointer<T>> targets) => _op('RemoveRelation', targets);

  Op _op(String op, List<Pointer<T>> targets) {
    // An empty list is a 500: the server reads `objects[0].className`
    // (`getObjectType` in SchemaController.js).
    if (targets.isEmpty) {
      throw ArgumentError.value(targets, 'targets', 'must not be empty');
    }
    return Op._(_key, {
      '__op': op,
      'objects': [for (final p in targets) p.encode(_schema)],
    });
  }
}
