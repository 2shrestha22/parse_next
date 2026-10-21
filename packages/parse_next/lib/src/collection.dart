part of 'client.dart';

final class Collection<T, F, O> {
  Collection._(this._client, this._schema);

  final ParseClient _client;
  final ParseSchema<T, F, O> _schema;

  String get _path => '/classes/${_schema.className}';
  String _object(String id) => '$_path/${Uri.encodeComponent(id)}';

  /// Null fields are left out. The returned [Doc] includes the fields a
  /// `beforeSave` trigger changed, and its [Doc.updatedAt] is
  /// [Doc.createdAt], since the create response carries no `updatedAt`.
  ///
  /// [id] is the new object's id, which the server accepts only with
  /// `allowCustomObjectId`. [context] reaches the triggers as
  /// `request.context`; in a browser it is sent only when the server's
  /// `allowHeaders` lists `X-Parse-Cloud-Context`.
  Future<Doc<T>> create(
    T value, {
    Acl? acl,
    String? id,
    Map<String, Object?>? context,
  }) async {
    final body = _createBody(value, acl, id);
    final response = await request(
      _client,
      'POST',
      _path,
      body: body,
      context: context,
    );
    return _createdDoc(body, response);
  }

  Query<T, F, O> query() => Query._(this);

  Query<T, F, O> where(Cond<T> Function(F f) build) => query().where(build);

  Future<Doc<T>> get(String id) async =>
      Doc.decode(await request(_client, 'GET', _object(id)), _schema);

  /// Sends the ops in one request, which the server applies atomically.
  Future<UpdateResult<T>> update(
    String id,
    List<Op> Function(O ops) build, {
    Map<String, Object?>? context,
  }) async {
    final body = _updateBody(build);
    final response = await request(
      _client,
      'PUT',
      _object(id),
      body: body,
      context: context,
    );
    return UpdateResult._(_schema, body, response);
  }

  /// Overwrites every field except relations; the ACL changes only when
  /// [acl] is given.
  Future<UpdateResult<T>> replace(
    String id,
    T value, {
    Acl? acl,
    Map<String, Object?>? context,
  }) async {
    final body = _replaceBody(value, acl);
    final response = await request(
      _client,
      'PUT',
      _object(id),
      body: body,
      context: context,
    );
    return UpdateResult._(_schema, body, response);
  }

  Future<void> delete(String id, {Map<String, Object?>? context}) async {
    await request(_client, 'DELETE', _object(id), context: context);
  }

  Json _createBody(T value, Acl? acl, [String? id]) => Json({
    ..._withoutNulls(_schema.encode(value)),
    if (acl != null) 'ACL': acl.toJson(),
    'objectId': ?id,
  });

  Doc<T> _createdDoc(Json sent, Json response) =>
      Doc.decode(_created(sent, response), _schema);

  Json _updateBody(List<Op> Function(O ops) build) {
    final ops = build(_schema.ops);
    if (ops.isEmpty) throw ArgumentError.value(ops, 'build', 'returned no ops');
    final body = Json({});
    // Fields with a `MapOps` key op, which takes the whole field.
    final maps = <String>{};
    for (final op in ops) {
      final dot = op._key.indexOf('.');
      final field = dot < 0 ? op._key : op._key.substring(0, dot);
      final clash = dot < 0
          ? body.containsKey(field) || maps.contains(field)
          : body.containsKey(field) || !maps.add(field);
      if (clash) {
        throw ArgumentError.value(op._key, 'build', 'has two ops on one field');
      }
      body[op._key] = op._json;
    }
    return body;
  }

  Json _replaceBody(T value, Acl? acl) => Json({
    // A PUT merges into the stored object, so a null must be sent as a
    // Delete or the old value survives.
    for (final MapEntry(:key, value: v) in _schema.encode(value).entries)
      key: v ?? _delete,
    if (acl != null) 'ACL': acl.toJson(),
  });
}

/// Not sent as null: on Mongo a stored null Polygon makes every later read of
/// the object a 500 (PolygonCoder in MongoTransform.js).
Json _withoutNulls(Json encoded) =>
    Json({for (final MapEntry(:key, value: v) in encoded.entries) key: ?v});

/// The object a create stored, from what was [sent] and the [response],
/// which has no `updatedAt`.
Json _created(Json sent, Json response) => Json(
  {...sent, ...response, 'updatedAt': response['createdAt']}
    // A field a beforeSave trigger unset comes back as a Delete op
    // (`_updateResponseWithData` in parse-server's RestWrite.js).
    ..removeWhere((_, v) => v is Map<String, Object?> && v['__op'] == 'Delete'),
);

/// What [Collection.update] or [Collection.replace] changed.
final class UpdateResult<T> {
  UpdateResult._(this._schema, this._sent, Json response)
    : updatedAt = response.require<DateTime>('updatedAt'),
      _response = response;

  final ParseSchema<T, Object?, Object?> _schema;
  final Json _sent;
  final Json _response;
  final DateTime updatedAt;

  /// [doc] after this change: the values sent, then the values the server
  /// reported, which are the results of `increment`, `add`, `addUnique` and
  /// `remove` and every field a `beforeSave` trigger changed.
  Doc<T> applyTo(Doc<T> doc) {
    final json = <String, Object?>{
      ..._schema.encode(doc.data),
      if (doc.acl case final acl?) 'ACL': acl.toJson(),
    };
    for (final MapEntry(:key, :value) in _sent.entries) {
      switch (value) {
        case {'__op': 'Delete'}:
          _put(json, key, null);
        // Any other op's result comes back in the response; a relation op's
        // has no value to keep.
        case {'__op': _}:
          break;
        default:
          _put(json, key, value);
      }
    }
    // After `meta.n` the server reports `{"meta": {"n": 3}}`, only the leaves
    // that changed, not the whole map.
    final dotted = {
      for (final k in _sent.keys)
        if (k.contains('.')) k.substring(0, k.indexOf('.')),
    };
    for (final MapEntry(:key, :value) in _response.entries) {
      if (key == 'updatedAt') continue;
      if ((dotted.contains(key), json[key], value) case (
        true,
        final Map<String, Object?> old,
        final Map<String, Object?> leaves,
      )) {
        json[key] = _merge(old, leaves);
      } else {
        _put(
          json,
          key,
          value is Map && value['__op'] == 'Delete' ? null : value,
        );
      }
    }
    return Doc.decode(
      Json({
        ...json,
        'objectId': doc.id,
        'createdAt': doc.createdAt.toIso8601String(),
        'updatedAt': _response['updatedAt'],
      }),
      _schema,
    );
  }
}

Map<String, Object?> _merge(
  Map<String, Object?> old,
  Map<String, Object?> leaves,
) => {
  ...old,
  for (final MapEntry(:key, :value) in leaves.entries)
    key: switch ((old[key], value)) {
      (final Map<String, Object?> o, final Map<String, Object?> l) => _merge(
        o,
        l,
      ),
      _ => value,
    },
};

/// Sets [value] at [key], which may be a dotted path into a map field, where
/// null removes the key as the server does.
void _put(Map<String, Object?> json, String key, Object? value) {
  final path = key.split('.');
  var target = json;
  for (final step in path.take(path.length - 1)) {
    target = switch (target[step]) {
      final Map<String, Object?> m => target[step] = {...m},
      _ => target[step] = <String, Object?>{},
    };
  }
  if (value == null && path.length > 1) {
    target.remove(path.last);
  } else {
    target[path.last] = value;
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

/// [setKey], [incrementKey] and [unsetKey] change one top-level key of the
/// map and leave the rest. Throws [ArgumentError] for a dotted key and, in
/// `Collection.update`, for two of them on one map: when the class has a
/// trigger, parse-server 9.9.0 stores a deeper path one level up, and
/// answers two keys of one map with a 500 on Mongo (the JS SDK expands each
/// into the whole map, in `_getSaveJSON`).
final class MapOps extends SetOps<Map<String, Object?>> {
  const MapOps(String key) : super(key, encodeValue);

  Op setKey(String key, Object? value) => _at(key, encodeValue(value));

  Op incrementKey(String key, num by) =>
      _at(key, {'__op': 'Increment', 'amount': by});

  Op unsetKey(String key) => _at(key, _delete);

  Op _at(String key, Object? json) => key.isEmpty || key.contains('.')
      ? throw ArgumentError.value(key, 'key', 'must be one key, without a dot')
      : Op._('$_key.$key', json);
}

final class NullableMapOps extends MapOps {
  const NullableMapOps(super.key);

  Op unset() => Op._(_key, _delete);
}

final class RelationOps<T> {
  const RelationOps(this._key, this._schema);

  final String _key;
  final ParseSchema<T, Object?, Object?> _schema;

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
