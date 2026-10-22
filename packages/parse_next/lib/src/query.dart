part of 'client.dart';

/// A `where` condition on objects of class [T]. Combine with `&` and `|`,
/// and negate with `~`.
final class Cond<T> {
  const Cond._(this._where);

  /// Matches no object on either backend: an empty `$in` is `IS NULL` on
  /// Postgres, which never holds for `objectId`.
  const Cond._nothing()
    : _where = const {
        'objectId': {r'$in': <Object?>[]},
      };

  final Map<String, Object?> _where;

  /// One object when the two share no key, `$and` otherwise.
  Cond<T> operator &(Cond<T> other) =>
      _keys(_where).any(_keys(other._where).contains)
      ? Cond._({
          r'$and': [_where, other._where],
        })
      : Cond._({..._where, ...other._where});

  Cond<T> operator |(Cond<T> other) => Cond._({
    r'$or': [_where, other._where],
  });

  /// Sent as `$nor`. On Mongo it also matches objects that lack the field.
  Cond<T> operator ~() => Cond._({
    r'$nor': [_where],
  });
}

/// The keys of [where], with the ones Mongo writes for it: parse-server
/// turns a `$containedBy` into a top-level `$nor` and a `$text` into a
/// top-level `$text`, so two of either in one object overwrite each other
/// (`transformWhere` in MongoTransform.js).
Set<String> _keys(Map<String, Object?> where) => {
  for (final MapEntry(:key, :value) in where.entries) ...[
    key,
    if (value case {r'$containedBy': _}) r'$nor',
    if (value case {r'$text': _}) r'$text',
  ],
};

/// A sort key on class [T], from a comparable field's `asc` or `desc`.
final class Sort<T> {
  const Sort._(this._key);

  final String _key;
}

/// The fields every class has. Generated `XFields` classes extend it.
abstract base class Fields<T> {
  const Fields();

  ComparableField<T, String> get id => ComparableField('objectId');
  DateField<T> get createdAt => DateField('createdAt');
  DateField<T> get updatedAt => DateField('updatedAt');
}

/// For bytes, and the base of every field.
final class ExistsField<T> {
  const ExistsField(this._key);

  final String _key;

  Cond<T> exists([bool value = true]) => _cond({r'$exists': value});

  Cond<T> _cond(Object? constraint) => Cond._({_key: constraint});
}

/// A field whose values can be compared for equality.
final class Field<T, V> extends ExistsField<T> {
  const Field(super._key, [this._encode = _same]);

  final Object? Function(V) _encode;

  Object? _wire(V value) => _encode(value);

  Cond<T> eq(V value) => _cond(_wire(value));
  Cond<T> ne(V value) => _cond({r'$ne': _wire(value)});

  /// An empty list matches nothing, on both backends.
  Cond<T> oneOf(List<V> values) =>
      values.isEmpty ? Cond._nothing() : _cond({r'$in': _all(values)});

  /// On Mongo an absent field matches; Postgres compiles `$nin` to `NOT IN`,
  /// which never matches null (`buildWhereClause` in
  /// PostgresStorageAdapter.js).
  Cond<T> noneOf(List<V> values) => _cond({r'$nin': _all(values)});

  /// Matches when this field equals [key] of any object [query] finds. Only
  /// the where part of [query] is used.
  Cond<T> matchesKey<Q, QF>(
    Query<Q, QF, Object?> query,
    Field<Q, V> Function(QF f) key,
  ) => _cond({r'$select': _keyQuery(query, key)});

  /// Matches when this field equals [key] of no object [query] finds.
  Cond<T> notMatchesKey<Q, QF>(
    Query<Q, QF, Object?> query,
    Field<Q, V> Function(QF f) key,
  ) => _cond({r'$dontSelect': _keyQuery(query, key)});

  List<Object?> _all(List<V> values) => [for (final v in values) _wire(v)];

  Map<String, Object?> _keyQuery<Q, QF>(
    Query<Q, QF, Object?> query,
    Field<Q, V> Function(QF f) key,
  ) => {'query': query._subquery(), 'key': key(query._fields)._key};
}

/// Strings compare by the database collation: binary on Mongo, the
/// database's locale (`en_US.utf8` by default) on Postgres. Sorting puts
/// absent values first on Mongo and last on Postgres.
final class ComparableField<T, V> extends Field<T, V> {
  const ComparableField(super._key, [super._encode]);

  Cond<T> gt(V value) => _cond({r'$gt': _wire(value)});
  Cond<T> gte(V value) => _cond({r'$gte': _wire(value)});
  Cond<T> lt(V value) => _cond({r'$lt': _wire(value)});
  Cond<T> lte(V value) => _cond({r'$lte': _wire(value)});

  Sort<T> get asc => Sort._(_key);
  Sort<T> get desc => Sort._('-$_key');
}

/// On Postgres, `ne`, `oneOf` and `noneOf` fail with a 500: it passes a
/// `{"__type":"Date"}` inside `$ne`, `$in` or `$nin` to SQL unconverted
/// (`buildWhereClause` in PostgresStorageAdapter.js).
final class DateField<T> extends ComparableField<T, DateTime> {
  const DateField(String key) : super(key, encodeDate);
}

final class StringField<T> extends ComparableField<T, String> {
  const StringField(super._key);

  /// Postgres cannot unquote a `\E` in [prefix] and matches it wrongly
  /// (`literalizeRegexPart` in PostgresStorageAdapter.js).
  Cond<T> startsWith(String prefix) => _cond({r'$regex': '^${_quote(prefix)}'});

  /// Postgres cannot unquote a `\E` in [suffix], as in [startsWith].
  Cond<T> endsWith(String suffix) => _cond({r'$regex': '${_quote(suffix)}\$'});

  /// Matches [text] anywhere in the string. Postgres cannot unquote a `\E`
  /// in [text], as in [startsWith].
  Cond<T> contains(String text) => _cond({r'$regex': _quote(text)});

  /// [pattern] goes to the database unchanged: PCRE on Mongo, POSIX on
  /// Postgres, so keep to the syntax both share.
  Cond<T> matches(String pattern, {bool caseInsensitive = false}) =>
      _cond({r'$regex': pattern, if (caseInsensitive) r'$options': 'i'});

  /// Matches [search] after stemming: on Mongo any of its words, or a
  /// "quoted phrase". Postgres passes it to `to_tsquery`, where a space is a
  /// syntax error (500), so keep to one word there.
  ///
  /// On Mongo, a class can have one text index and `$text` searches it
  /// whatever the field, so use this on one field per class. Only a find
  /// creates that index, so a `count` before the first find is a 500
  /// (`createTextIndexesIfNeeded` in MongoStorageAdapter.js). Mongo also
  /// rejects it inside `|` and together with `near`.
  Cond<T> fullText(
    String search, {
    String? language,
    bool? caseSensitive,
    bool? diacriticSensitive,
  }) => _cond({
    r'$text': {
      r'$search': {
        r'$term': search,
        r'$language': ?language,
        r'$caseSensitive': ?caseSensitive,
        r'$diacriticSensitive': ?diacriticSensitive,
      },
    },
  });
}

/// The JS SDK's quoting: a `\E` inside ends the quote, adds a literal `\E`
/// and quotes again.
String _quote(String s) => '\\Q${s.replaceAll(r'\E', r'\E\\E\Q')}\\E';

final class ListField<T, E> extends ExistsField<T> {
  const ListField(super._key, [this._encode = _same]);

  final Object? Function(E) _encode;

  /// Sent as `$all`: Postgres answers an equality on an array with a 500.
  Cond<T> contains(E value) => containsAll([value]);

  /// An empty list matches nothing.
  Cond<T> containsAll(List<E> values) => _cond({r'$all': _all(values)});

  /// Matches a list holding at least one of [values]. An empty list matches
  /// nothing, on both backends.
  Cond<T> containsAny(List<E> values) =>
      values.isEmpty ? Cond._nothing() : _cond({r'$in': _all(values)});

  /// Matches a list whose every element is one of [values]; an empty list
  /// matches. An absent list matches on Mongo only, not on Postgres or in a
  /// live query.
  Cond<T> containedBy(List<E> values) => _cond({r'$containedBy': _all(values)});

  List<Object?> _all(List<E> values) => [for (final v in values) _encode(v)];
}

extension StringListFieldX<T> on ListField<T, String> {
  /// Matches a list with, for each of [prefixes], an element that starts
  /// with it.
  Cond<T> containsAllStartingWith(List<String> prefixes) => _cond({
    r'$all': [
      for (final p in prefixes) {r'$regex': '^${_quote(p)}'},
    ],
  });
}

/// A field `Query.include` accepts.
sealed class Includable<T> {
  String get _key;
}

final class _IncludePath<T> implements Includable<T> {
  const _IncludePath(this._key);

  @override
  final String _key;
}

final class PointerField<T, P, PF> extends Field<T, Pointer<P>>
    implements Includable<T> {
  const PointerField(super._key, this._target);

  final ParseSchema<P, PF, Object?> _target;

  @override
  Object? _wire(Pointer<P> value) => value.encode(_target);

  Cond<T> isId(String id) => eq(Pointer<P>(id));

  /// Uses only the where part of [query]; throws [ArgumentError] when it
  /// has `include`, `orderBy`, `limit` or `skip`.
  Cond<T> matchesQuery(Query<P, Object?, Object?> query) =>
      _cond({r'$inQuery': query._subquery()});

  /// Matches a pointer to none of what [query] finds, or no pointer. Uses
  /// only the where part of [query], as [matchesQuery].
  Cond<T> notMatchesQuery(Query<P, Object?, Object?> query) =>
      _cond({r'$notInQuery': query._subquery()});

  /// Includes a pointer field of the target too, as `author.profile`.
  Includable<T> then(Includable<P> Function(PF f) pick) =>
      _IncludePath('$_key.${pick(_target.fields)._key}');
}

final class PointerListField<T, P, PF> extends ListField<T, Pointer<P>>
    implements Includable<T> {
  PointerListField(String key, this._target)
    : super(key, (p) => p.encode(_target));

  final ParseSchema<P, PF, Object?> _target;

  /// Includes a pointer field of the targets too, as `coauthors.profile`.
  Includable<T> then(Includable<P> Function(PF f) pick) =>
      _IncludePath('$_key.${pick(_target.fields)._key}');
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

  /// Within [km] of [point], unsorted, so that it combines with `orderBy`
  /// and `|`, unlike [near].
  Cond<T> withinKm(GeoPoint point, double km) => _cond({
    r'$geoWithin': {
      r'$centerSphere': [
        [point.longitude, point.latitude],
        km / 6371,
      ],
    },
  });

  Cond<T> withinBox(GeoPoint southwest, GeoPoint northeast) => _cond({
    r'$within': {
      r'$box': [southwest.toJson(), northeast.toJson()],
    },
  });

  /// Planar, on longitude and latitude, on both backends.
  Cond<T> withinPolygon(Polygon polygon) => _cond({
    r'$geoWithin': {
      // GeoPoints, not a Polygon value: here both adapters read Polygon
      // coordinates as [longitude, latitude], the reverse of the stored
      // form (`$geoWithin` in MongoTransform.js and
      // PostgresStorageAdapter.js).
      r'$polygon': [for (final p in polygon.points) p.toJson()],
    },
  });
}

final class PolygonField<T> extends ExistsField<T> {
  const PolygonField(super._key);

  /// Matches a polygon that holds [point].
  Cond<T> containsPoint(GeoPoint point) => _cond({
    r'$geoIntersects': {r'$point': point.toJson()},
  });
}

/// Postgres has no equality for files (`buildWhereClause` in
/// PostgresStorageAdapter.js); there `eq` and `ne` fail.
final class FileField<T> extends Field<T, ParseFile> {
  const FileField(String key) : super(key, _fileJson);
}

Object? _fileJson(ParseFile f) => f.toJson();

final class MapField<T> extends ExistsField<T> {
  const MapField(super._key);

  /// The value at [path] inside the map, a key or a dotted path such as
  /// `'a.b'`. Values are encoded as [encodeValue] does.
  ComparableField<T, Object?> at(String path) =>
      ComparableField('$_key.$path', encodeValue);
}

/// A relation on class [T] whose members are of class [R].
final class RelationField<T, R> {
  const RelationField(this._key, this._owner, this._member);

  final String _key;
  final ParseSchema<T, Object?, Object?> _owner;
  final ParseSchema<R, Object?, Object?> _member;

  /// Matches the [T] objects whose relation holds [member]. A live query
  /// never matches it: the LiveQuery server sees no relation members.
  Cond<T> has(Pointer<R> member) => Cond._({_key: member.encode(_member)});

  /// The members of this relation on the [T] object [ownerId]; a condition
  /// for a query on [R].
  Cond<R> of(String ownerId) => Cond._({
    r'$relatedTo': {'object': Pointer<T>(ownerId).encode(_owner), 'key': _key},
  });
}

/// Which member of a Mongo replica set serves a query; Postgres ignores it.
enum ReadPreference {
  primary,
  primaryPreferred,
  secondary,
  secondaryPreferred,
  nearest;

  String get _wire =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();
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
    Map<String, Object?> options = const {},
  }) : _where = where,
       _include = include,
       _order = order,
       _limit = limit,
       _skip = skip,
       _options = options;

  static const _pageSize = 100;

  final Collection<T, F, O> _collection;
  final Cond<T>? _where;
  final List<String> _include;
  final List<String> _order;
  final int? _limit;
  final int? _skip;

  /// `includeAll`, `hint`, `comment` and `readPreference`, sent as they are.
  final Map<String, Object?> _options;

  F get _fields => _collection._schema.fields;

  Query<T, F, O> _with({
    Cond<T>? where,
    List<String>? include,
    List<String>? order,
    int? limit,
    int? skip,
    Map<String, Object?>? options,
  }) => Query._(
    _collection,
    where: where ?? _where,
    include: include ?? _include,
    order: order ?? _order,
    limit: limit ?? _limit,
    skip: skip ?? _skip,
    options: options ?? _options,
  );

  Query<T, F, O> _option(String key, Object value) =>
      _with(options: {..._options, key: value});

  /// Combines with any earlier condition using `&`.
  Query<T, F, O> where(Cond<T> Function(F f) build) {
    final cond = build(_fields);
    return _with(where: _where == null ? cond : _where & cond);
  }

  Query<T, F, O> include(Includable<T> Function(F f) pick) =>
      _with(include: [..._include, pick(_fields)._key]);

  /// Includes every pointer field, one level deep.
  Query<T, F, O> includeAll() => _option('includeAll', true);

  /// Appends a sort key; earlier calls sort first.
  Query<T, F, O> orderBy(Sort<T> Function(F f) pick) =>
      _with(order: [..._order, pick(_fields)._key]);

  /// Appends a sort by [StringField.fullText] relevance, best first, on
  /// Mongo; Postgres ignores it.
  Query<T, F, O> orderByTextScore() => _with(order: [..._order, r'$score']);

  Query<T, F, O> limit(int n) => _with(limit: RangeError.checkNotNegative(n));

  Query<T, F, O> skip(int n) => _with(skip: RangeError.checkNotNegative(n));

  /// The Mongo index to use, by name; an unknown name fails the query.
  /// Postgres ignores it.
  Query<T, F, O> hint(String index) => _option('hint', index);

  /// Shown with the query in Mongo's logs and profiler.
  Query<T, F, O> comment(String text) => _option('comment', text);

  Query<T, F, O> readPreference(ReadPreference preference) =>
      _option('readPreference', preference._wire);

  /// Returns at most [limit], or 100 without one: the server's default, sent
  /// explicitly. [stream] fetches every match.
  Future<List<Doc<T>>> find() => _find(_body(limit: _limit ?? _pageSize));

  /// [find] and [count] in one request.
  Future<({List<Doc<T>> docs, int count})> findAndCount() async {
    final response = await _get(
      Json({..._body(limit: _limit ?? _pageSize), 'count': 1}),
    );
    return (
      docs: [
        for (final r in response.requireList<Json>('results'))
          Doc.decode(r, _collection._schema),
      ],
      count: response.require<int>('count'),
    );
  }

  /// Like [find], but a row that does not match the model is an [Err] with
  /// a [DecodeError] whose [DecodeError.id] names the row, in place of
  /// failing the whole page. A failed request still throws.
  Future<List<Result<Doc<T>>>> tryFind() async => [
    for (final r in await _rows(_body(limit: _limit ?? _pageSize)))
      _tryDecode(r),
  ];

  Future<Doc<T>?> first() async => (await _find(_body(limit: 1))).firstOrNull;

  /// The object [id] if it also matches this query, with its includes.
  /// Throws [ObjectNotFound] otherwise, as `Collection.get` does.
  Future<Doc<T>> get(String id) async =>
      await where((_) => Cond._({'objectId': id})).first() ??
      (throw const ObjectNotFound('Object not found.', status: 404));

  /// Counts every match; `include`, `orderBy`, `limit` and `skip` are not
  /// sent.
  Future<int> count() async {
    final response = await _get(
      Json({
        if (_where case final w?) 'where': w._where,
        'count': 1,
        'limit': 0,
      }),
    );
    return response.require<int>('count');
  }

  /// The distinct values of [field] among the matches, undecoded and in no
  /// set order; `include`, `orderBy`, `limit` and `skip` are not sent. A
  /// Date comes back as `{"__type":"Date"}` on Mongo and as an ISO string on
  /// Postgres. Needs [ParseClient.masterKey].
  Future<List<Object?>> distinct(ExistsField<T> Function(F f) field) async {
    final response = await request(
      _client,
      'POST',
      '/aggregate/${_collection._schema.className}',
      body: Json({
        '_method': 'GET',
        if (_where case final w?) 'where': w._where,
        'distinct': field(_fields)._key,
      }),
    );
    return response.require<List<Object?>>('results');
  }

  /// The database's plan for [find]: an object on Mongo, a list of rows on
  /// Postgres. Needs [ParseClient.masterKey].
  Future<Object?> explain() async => (await _get(
    Json({..._body(limit: _limit ?? _pageSize), 'explain': true}),
  ))['results'];

  /// Every match, fetched 100 at a time in objectId order. Throws
  /// [StateError] when the query has [orderBy], [skip] or [limit], which
  /// the objectId cursor replaces.
  Stream<Doc<T>> stream() {
    if (_order.isNotEmpty || _skip != null || _limit != null) {
      throw StateError(
        'stream() pages by objectId; '
        'remove orderBy, skip and limit',
      );
    }
    return _pages();
  }

  Stream<Doc<T>> _pages() async* {
    var page = _with(order: const ['objectId']);
    while (true) {
      final docs = await page._find(page._body(limit: _pageSize));
      for (final d in docs) {
        yield d;
      }
      if (docs.length < _pageSize) return;
      final after = Cond<T>._({
        'objectId': {r'$gt': docs.last.id},
      });
      page = page._with(where: _where == null ? after : _where & after);
    }
  }

  /// Changes to matching objects as the server sees them, over one
  /// WebSocket per [ParseClient] that opens with the first listener and
  /// closes when the last one cancels.
  ///
  /// The stream emits [Subscribed] each time the server confirms the
  /// subscription: first after listening, then after every reconnect, and
  /// [Disconnected] when the connection is lost. Changes between the two may
  /// be missing and are never replayed, so (re)load the state after each
  /// [Subscribed]. A lost connection is retried after 1 s, doubling up to
  /// 30 s, and never ends the stream.
  ///
  /// With [watch], an object that still matches is reported as [Updated]
  /// only when one of those fields changed; `create`, `enter`, `leave` and
  /// `delete` are always reported.
  ///
  /// The subscription keeps the session of the moment it is listened to;
  /// a later login or logout does not change it, and one made without a
  /// session sees only what anyone may read. An invalid token is not an
  /// error: the server treats it as no session.
  ///
  /// A server error for this subscription, such as an invalid `matches`
  /// pattern (102), is emitted as its [ParseException] with the HTTP status
  /// the server gives that code elsewhere, and ends the stream. Only classes
  /// in the server's `liveQuery.classNames` publish changes; a subscription
  /// to any other class is accepted and never emits.
  ///
  /// The server matches in JavaScript (QueryTools.js): strings compare by
  /// UTF-16 code unit, as on Mongo, and `withinBox` leaves out its edges.
  /// Throws [ArgumentError] for the conditions it cannot match:
  /// [StringField.fullText], [PointerField.matchesQuery],
  /// [PointerField.notMatchesQuery], [Field.matchesKey],
  /// [Field.notMatchesKey], [RelationField.of], any condition on `createdAt`
  /// or `updatedAt`, `oneOf` and `noneOf` on a date, `contains` on a pointer
  /// list, `containsAllStartingWith`, and an empty `containsAll`. Throws [StateError] when the query has [include],
  /// [orderBy], [limit], [skip] or another option, which a live query cannot
  /// apply.
  Stream<LiveEvent<T>> live({List<ExistsField<T>> Function(F f)? watch}) {
    if (_include.isNotEmpty ||
        _order.isNotEmpty ||
        _skip != null ||
        _limit != null ||
        _options.isNotEmpty) {
      throw StateError(
        'live() matches single objects; '
        'remove include, orderBy, skip, limit and options',
      );
    }
    return _client._live.subscribe(_collection._schema, {
      'where': _liveWhere(_where?._where ?? const {}),
      if (watch != null) 'watch': [for (final f in watch(_fields)) f._key],
    });
  }

  /// The [keys] of each match, or all but [exclude], undecoded; same paging
  /// as [find].
  Future<List<Json>> raw({
    List<String> keys = const [],
    List<String> exclude = const [],
  }) async {
    final response = await _get(
      Json({
        ..._body(limit: _limit ?? _pageSize),
        if (keys.isNotEmpty) 'keys': keys.join(','),
        if (exclude.isNotEmpty) 'excludeKeys': exclude.join(','),
      }),
    );
    return response.requireList<Json>('results');
  }

  ParseClient get _client => _collection._client;

  /// For `$inQuery`, `$notInQuery`, `$select` and `$dontSelect`, which use
  /// only the where part.
  Map<String, Object?> _subquery() {
    if (_include.isNotEmpty ||
        _order.isNotEmpty ||
        _limit != null ||
        _skip != null ||
        _options.isNotEmpty) {
      throw ArgumentError.value(
        this,
        'query',
        'must have only a where condition',
      );
    }
    return {
      'where': _where?._where ?? const <String, Object?>{},
      'className': _collection._schema.className,
    };
  }

  Json _body({required int limit}) => Json({
    if (_where case final w?) 'where': w._where,
    if (_include.isNotEmpty) 'include': _include.join(','),
    if (_order.isNotEmpty) 'order': _order.join(','),
    'limit': limit,
    'skip': ?_skip,
    ..._options,
  });

  /// A POST read as a GET (`allowMethodOverride` in middlewares.js), as the
  /// JS SDK sends every query: in a URL, a `where` of about 1,000 ids is
  /// over Node's 16 KB header limit and fails with 431.
  Future<Json> _get(Json body) => request(
    _client,
    'POST',
    _collection._path,
    body: Json({'_method': 'GET', ...body}),
  );

  Future<List<Doc<T>>> _find(Json body) async => [
    for (final r in await _rows(body)) Doc.decode(r, _collection._schema),
  ];

  Future<List<Json>> _rows(Json body) async =>
      (await _get(body)).requireList<Json>('results');

  Result<Doc<T>> _tryDecode(Json row) {
    try {
      return Ok(Doc.decode(row, _collection._schema));
    } on DecodeError catch (e) {
      return Err(
        DecodeError(
          e.key,
          e.message,
          id: switch (row['objectId']) {
            final String id => id,
            _ => null,
          },
        ),
      );
    }
  }
}
