part of 'client.dart';

/// A `where` condition on objects of class [T]. Combine with `&` and `|`.
final class Cond<T> {
  const Cond._(this._where);

  final Map<String, Object?> _where;

  /// One object when the two share no key, `$and` otherwise.
  Cond<T> operator &(Cond<T> other) => _where.keys.any(other._where.containsKey)
      ? Cond._({
          r'$and': [_where, other._where]
        })
      : Cond._({..._where, ...other._where});

  Cond<T> operator |(Cond<T> other) => Cond._({
        r'$or': [_where, other._where]
      });
}

/// A sort key on class [T], from a comparable field's `asc` or `desc`.
final class Sort<T> {
  const Sort._(this._key);

  final String _key;
}

/// The fields every class has. Generated `XFields` classes extend it.
abstract base class Fields<T> {
  const Fields();

  ComparableField<T, String> get id => ComparableField('objectId');
  ComparableField<T, DateTime> get createdAt =>
      ComparableField('createdAt', encodeDate);
  ComparableField<T, DateTime> get updatedAt =>
      ComparableField('updatedAt', encodeDate);
}

/// For maps, files, bytes and polygons. Postgres has no equality for maps,
/// files or bytes (`buildWhereClause` in PostgresStorageAdapter.js).
final class ExistsField<T> {
  const ExistsField(this._key);

  final String _key;

  Cond<T> exists([bool value = true]) => _cond({r'$exists': value});

  Cond<T> _cond(Object? constraint) => Cond._({_key: constraint});
}

final class Field<T, V> extends ExistsField<T> {
  const Field(super._key, [this._encode = _same]);

  final Object? Function(V) _encode;

  Cond<T> eq(V value) => _cond(_encode(value));
  Cond<T> ne(V value) => _cond({r'$ne': _encode(value)});

  /// Throws [ArgumentError] for an empty list: Postgres turns `$in: []` into
  /// `IS NULL` (`buildWhereClause` in PostgresStorageAdapter.js) while Mongo
  /// matches nothing.
  Cond<T> oneOf(List<V> values) {
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }
    return _cond({r'$in': _all(values)});
  }

  /// On Mongo an absent field matches; Postgres compiles `$nin` to `NOT IN`,
  /// which never matches null (`buildWhereClause` in
  /// PostgresStorageAdapter.js).
  Cond<T> noneOf(List<V> values) => _cond({r'$nin': _all(values)});

  List<Object?> _all(List<V> values) => [for (final v in values) _encode(v)];
}

/// Strings compare by the database collation: binary on Mongo, the
/// database's locale (`en_US.utf8` by default) on Postgres. Sorting puts
/// absent values first on Mongo and last on Postgres.
final class ComparableField<T, V> extends Field<T, V> {
  const ComparableField(super._key, [super._encode]);

  Cond<T> gt(V value) => _cond({r'$gt': _encode(value)});
  Cond<T> gte(V value) => _cond({r'$gte': _encode(value)});
  Cond<T> lt(V value) => _cond({r'$lt': _encode(value)});
  Cond<T> lte(V value) => _cond({r'$lte': _encode(value)});

  Sort<T> get asc => Sort._(_key);
  Sort<T> get desc => Sort._('-$_key');
}

final class StringField<T> extends ComparableField<T, String> {
  const StringField(super._key);

  /// Throws [ArgumentError] when [prefix] contains `\E`, which Postgres
  /// cannot unquote (`literalizeRegexPart` in PostgresStorageAdapter.js).
  Cond<T> startsWith(String prefix) {
    if (prefix.contains(r'\E')) {
      throw ArgumentError.value(prefix, 'prefix', r'must not contain \E');
    }
    return _cond({r'$regex': '^\\Q$prefix\\E'});
  }

  /// [pattern] goes to the database unchanged: PCRE on Mongo, POSIX on
  /// Postgres, so keep to the syntax both share.
  Cond<T> matches(String pattern, {bool caseInsensitive = false}) => _cond({
        r'$regex': pattern,
        if (caseInsensitive) r'$options': 'i',
      });

  /// Matches [word] after stemming. Throws [ArgumentError] for more than one
  /// word: Postgres passes the term to `to_tsquery`, where a space is a
  /// syntax error (500), and Mongo would match any of the words.
  ///
  /// On Mongo, a class can have one text index and `$text` searches it
  /// whatever the field, so use this on one field per class. Only a find
  /// creates that index, so a `count` before the first find is a 500
  /// (`createTextIndexesIfNeeded` in MongoStorageAdapter.js). Mongo also
  /// rejects it inside `|` and together with `near`.
  Cond<T> fullText(String word) {
    if (word.trim().isEmpty || word.trim().contains(RegExp(r'\s'))) {
      throw ArgumentError.value(word, 'word', 'must be one word');
    }
    return _cond({
      r'$text': {
        r'$search': {r'$term': word.trim()}
      }
    });
  }
}

final class ListField<T, E> extends ExistsField<T> {
  const ListField(super._key, [this._encode = _same]);

  final Object? Function(E) _encode;

  /// Sent as `$all`: Postgres answers an equality on an array with a 500.
  Cond<T> contains(E value) => containsAll([value]);

  /// An empty list matches nothing.
  Cond<T> containsAll(List<E> values) => _cond({r'$all': _all(values)});

  List<Object?> _all(List<E> values) => [for (final v in values) _encode(v)];
}

/// A field `Query.include` accepts.
sealed class Includable<T> {
  String get _key;
}

final class PointerField<T, P> extends ExistsField<T> implements Includable<T> {
  const PointerField(super._key, this._target);

  final ParseSchema<P, Object?, Object?> _target;

  Cond<T> isId(String id) => _cond(Pointer<P>(id).encode(_target));

  /// Uses only the where part of [query]; throws [ArgumentError] when it
  /// has `include`, `orderBy`, `limit` or `skip`.
  Cond<T> matchesQuery(Query<P, Object?, Object?> query) {
    if (query._include.isNotEmpty ||
        query._order.isNotEmpty ||
        query._limit != null ||
        query._skip != null) {
      throw ArgumentError.value(
          query, 'query', 'must have only a where condition');
    }
    return _cond({
      r'$inQuery': {
        'where': query._where?._where ?? const <String, Object?>{},
        'className': _target.className,
      }
    });
  }
}

final class PointerListField<T, P> extends ListField<T, Pointer<P>>
    implements Includable<T> {
  PointerListField(String key, ParseSchema<P, Object?, Object?> target)
      : super(key, (p) => p.encode(target));
}

final class GeoField<T> extends ExistsField<T> {
  const GeoField(super._key);

  /// Sorts by distance, nearest first. Mongo rejects it inside `|`.
  Cond<T> near(GeoPoint point, {double? maxKm}) => _cond({
        r'$nearSphere': point.toJson(),
        // Radians, not `$maxDistanceInKilometers`: only the Mongo adapter
        // reads that (MongoTransform.js).
        if (maxKm != null) r'$maxDistance': maxKm / 6371,
      });

  Cond<T> withinBox(GeoPoint southwest, GeoPoint northeast) => _cond({
        r'$within': {
          r'$box': [southwest.toJson(), northeast.toJson()]
        }
      });

  /// Planar, on longitude and latitude, on both backends.
  Cond<T> withinPolygon(Polygon polygon) => _cond({
        r'$geoWithin': {
          // GeoPoints, not a Polygon value: here both adapters read Polygon
          // coordinates as [longitude, latitude], the reverse of the stored
          // form (`$geoWithin` in MongoTransform.js and
          // PostgresStorageAdapter.js).
          r'$polygon': [for (final p in polygon.points) p.toJson()]
        }
      });
}

/// A relation on class [T] whose members are of class [R].
final class RelationField<T, R> {
  const RelationField(this._key, this._owner);

  final String _key;
  final ParseSchema<T, Object?, Object?> _owner;

  /// The members of this relation on the [T] object [ownerId]; a condition
  /// for a query on [R].
  Cond<R> of(String ownerId) => Cond._({
        r'$relatedTo': {
          'object': Pointer<T>(ownerId).encode(_owner),
          'key': _key,
        }
      });
}

/// An immutable query; every builder returns a new one.
final class Query<T, F, O> {
  const Query._(
    this._collection, {
    Cond<T>? where,
    List<String> include = const [],
    List<String> order = const [],
    int? limit,
    int? skip,
  })  : _where = where,
        _include = include,
        _order = order,
        _limit = limit,
        _skip = skip;

  static const _pageSize = 100;

  final Collection<T, F, O> _collection;
  final Cond<T>? _where;
  final List<String> _include;
  final List<String> _order;
  final int? _limit;
  final int? _skip;

  F get _fields => _collection._schema.fields;

  Query<T, F, O> _with({
    Cond<T>? where,
    List<String>? include,
    List<String>? order,
    int? limit,
    int? skip,
  }) =>
      Query._(
        _collection,
        where: where ?? _where,
        include: include ?? _include,
        order: order ?? _order,
        limit: limit ?? _limit,
        skip: skip ?? _skip,
      );

  /// Combines with any earlier condition using `&`.
  Query<T, F, O> where(Cond<T> Function(F f) build) {
    final cond = build(_fields);
    return _with(where: _where == null ? cond : _where & cond);
  }

  Query<T, F, O> include(Includable<T> Function(F f) pick) =>
      _with(include: [..._include, pick(_fields)._key]);

  /// Appends a sort key; earlier calls sort first.
  Query<T, F, O> orderBy(Sort<T> Function(F f) pick) =>
      _with(order: [..._order, pick(_fields)._key]);

  Query<T, F, O> limit(int n) => _with(limit: RangeError.checkNotNegative(n));

  Query<T, F, O> skip(int n) => _with(skip: RangeError.checkNotNegative(n));

  /// Returns at most [limit], or 100 without one: the server's default, sent
  /// explicitly. [stream] fetches every match.
  Future<List<Doc<T>>> find() => _find(_params(limit: _limit ?? _pageSize));

  Future<Doc<T>?> first() async => (await _find(_params(limit: 1))).firstOrNull;

  /// Counts every match; `include`, `orderBy`, `limit` and `skip` are not
  /// sent.
  Future<int> count() async {
    final response = await request(_client, 'GET', _collection._path, query: {
      if (_where case final w?) 'where': jsonEncode(w._where),
      'count': '1',
      'limit': '0',
    });
    return response.require<int>('count');
  }

  /// Every match, fetched 100 at a time in objectId order. Throws
  /// [StateError] when the query has [orderBy], [skip] or [limit], which
  /// the objectId cursor replaces.
  Stream<Doc<T>> stream() {
    if (_order.isNotEmpty || _skip != null || _limit != null) {
      throw StateError('stream() pages by objectId; '
          'remove orderBy, skip and limit');
    }
    return _pages();
  }

  Stream<Doc<T>> _pages() async* {
    var page = _with(order: const ['objectId']);
    while (true) {
      final docs = await page._find(page._params(limit: _pageSize));
      for (final d in docs) {
        yield d;
      }
      if (docs.length < _pageSize) return;
      final after = Cond<T>._({
        'objectId': {r'$gt': docs.last.id}
      });
      page = page._with(where: _where == null ? after : _where & after);
    }
  }

  /// The listed [keys] of each match, undecoded; same paging as [find].
  Future<List<Json>> raw({required List<String> keys}) async {
    final response = await request(_client, 'GET', _collection._path, query: {
      ..._params(limit: _limit ?? _pageSize),
      'keys': keys.join(',')
    });
    return response.requireList<Json>('results');
  }

  ParseClient get _client => _collection._client;

  Map<String, String> _params({required int limit}) => {
        if (_where case final w?) 'where': jsonEncode(w._where),
        if (_include.isNotEmpty) 'include': _include.join(','),
        if (_order.isNotEmpty) 'order': _order.join(','),
        'limit': '$limit',
        if (_skip case final s?) 'skip': '$s',
      };

  Future<List<Doc<T>>> _find(Map<String, String> params) async {
    final response =
        await request(_client, 'GET', _collection._path, query: params);
    return [
      for (final r in response.requireList<Json>('results'))
        Doc.decode(r, _collection._schema),
    ];
  }
}
