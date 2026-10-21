part of 'client.dart';

/// Writes sent together through `POST /batch`, from [ParseClient.batch].
///
/// A server with `requestComplexity.batchRequestLimit` rejects a longer
/// batch as a whole with 107, unless it is sent with the master key
/// (`handleBatch` in batch.js); parse-server announces 100 as the coming
/// default. The JSON body is capped by the server's `maxUploadSize`, 20 MB
/// by default.
final class Batch {
  Batch._(this._client);

  final ParseClient _client;
  final _ops = <BatchOp<Object?>>[];
  bool _sent = false;

  /// Encoded as [Collection.create] does.
  BatchOp<Doc<T>> create<T, F, O>(
    Collection<T, F, O> collection,
    T value, {
    Acl? acl,
    String? id,
  }) {
    _check(collection);
    final body = collection._createBody(value, acl, id);
    return _add(
      'POST',
      collection._path,
      body,
      (r) => collection._createdDoc(body, r),
    );
  }

  /// Encoded as [Collection.update] does.
  BatchOp<UpdateResult<T>> update<T, F, O>(
    Collection<T, F, O> collection,
    String id,
    List<Op> Function(O ops) build,
  ) {
    _check(collection);
    final body = collection._updateBody(build);
    return _add(
      'PUT',
      collection._object(id),
      body,
      (r) => UpdateResult._(collection._schema, body, r),
    );
  }

  /// Encoded as [Collection.replace] does.
  BatchOp<UpdateResult<T>> replace<T, F, O>(
    Collection<T, F, O> collection,
    String id,
    T value, {
    Acl? acl,
  }) {
    _check(collection);
    final body = collection._replaceBody(value, acl);
    return _add(
      'PUT',
      collection._object(id),
      body,
      (r) => UpdateResult._(collection._schema, body, r),
    );
  }

  BatchOp<void> delete<T, F, O>(Collection<T, F, O> collection, String id) {
    _check(collection);
    return _add('DELETE', collection._object(id), null, (_) {});
  }

  /// Fills every [BatchOp.result]. Without [transaction], the items go 20 to
  /// a request, one request after another, as the JS SDK sends them; a
  /// failure of a request as a whole, such as [NetworkError], is thrown here
  /// and leaves the results of its items and the later ones unset.
  ///
  /// [context] reaches every item's triggers as `request.context`.
  ///
  /// With [transaction], one failing item rolls back every item, and the
  /// server answers with 500 `Internal server error.` without the item
  /// results (`handleBatch` in batch.js), so this throws [OtherParseError]
  /// with code 1. The server destroys the socket after that response (see
  /// [NetworkError]), so a transactional batch asks for its connection to be
  /// closed and the next call opens a fresh one.
  Future<void> send({
    bool transaction = false,
    Map<String, Object?>? context,
  }) async {
    if (_sent) throw StateError('This batch was already sent.');
    if (_ops.isEmpty) throw ArgumentError('A batch needs at least one item.');
    _sent = true;
    final size = transaction ? _ops.length : _chunk;
    for (var start = 0; start < _ops.length; start += size) {
      final chunk = _ops.sublist(start, min(start + size, _ops.length));
      final results = await _request<List<Object?>>(
        _client,
        'POST',
        '/batch',
        body: Json({
          'requests': [
            for (final op in chunk)
              {
                'method': op._method,
                // The server routes each item by its full path, mount
                // included.
                'path': '${_client._mount}${op._path}',
                'body': ?op._body,
              },
          ],
          if (transaction) 'transaction': true,
        }),
        persistent: !transaction,
        context: context,
      );
      if (results.length != chunk.length) {
        throw DecodeError(
          'batch',
          'expected ${chunk.length} results, got ${results.length}',
        );
      }
      for (var i = 0; i < chunk.length; i++) {
        chunk[i]._complete('[${start + i}]', results[i]);
      }
    }
  }

  static const _chunk = 20;

  void _check(Collection<Object?, Object?, Object?> collection) {
    if (_sent) throw StateError('This batch was already sent.');
    if (!identical(collection._client, _client)) {
      throw ArgumentError.value(
        collection,
        'collection',
        'belongs to another ParseClient',
      );
    }
  }

  BatchOp<R> _add<R>(
    String method,
    String path,
    Json? body,
    R Function(Json success) decode,
  ) {
    final op = BatchOp<R>._(method, path, body, decode);
    _ops.add(op);
    return op;
  }
}

/// One item of a [Batch], whose [result] is set once [Batch.send] completes.
final class BatchOp<R> {
  BatchOp._(this._method, this._path, this._body, this._decode);

  final String _method;
  final String _path;
  final Json? _body;
  final R Function(Json success) _decode;
  Result<R>? _result;

  /// An [Err] holds the exception the same call outside a batch would
  /// throw, with the HTTP status the server gives that code on its own
  /// (`handleParseErrors` in middlewares.js), or a [DecodeError].
  Result<R> get result =>
      _result ?? (throw StateError('The batch has not been sent.'));

  void _complete(String key, Object? item) {
    _result = switch (item) {
      {'success': final Map<String, Object?> success} => _ok(key, success),
      {'error': final Map<String, Object?> error} => Err(_error(Json(error))),
      _ => Err(DecodeError(key, 'expected success or error')),
    };
  }

  Result<R> _ok(String key, Map<String, Object?> success) {
    try {
      return Ok(_decode(Json(success)));
    } on DecodeError catch (e) {
      return Err(DecodeError('$key.${e.key}', e.message));
    }
  }

  ParseException _error(Json error) {
    final code = switch (error['code']) {
      final num n => n.toInt(),
      _ => null,
    };
    final message = switch (error['error']) {
      final String m => m,
      _ => '',
    };
    return _exception(code, message, _statusOf(code), _path);
  }
}
