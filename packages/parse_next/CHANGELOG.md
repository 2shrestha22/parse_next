## 0.3.0

- Breaking: `update` and `replace` return `UpdateResult`; `applyTo(doc)` gives the object as the server has it, op results and trigger changes included.
- Breaking: `ParseFile.url` is required and always sent.
- Breaking: `Disconnected` joins `LiveEvent`; pointer fields carry the target's fields type, relation fields its schema.
- `ParseClient(masterKey:)` for code on a server, with `Collection.aggregate`, `Query.distinct`, `Query.explain`, `saveConfig`, `deleteFile`, `startJob`, `push`, `schemas()` and `schema(name)`.
- Lists of `DateTime`, `GeoPoint`, `ParseFile` and `Map<String, Object?>` as typed fields; `Json.requireMapList` and `optMapList`.
- Queries are sent as POSTs read as GETs, so a `where` of thousands of ids no longer fails with 431.
- New conditions: pointer `eq`/`ne`/`oneOf`/`noneOf`, `notMatchesQuery`, `matchesKey`/`notMatchesKey`, `~` (nor), `endsWith`, string `contains`, `containedBy`, `containsAllStartingWith`, `withinKm`, polygon `containsPoint`, map `at()`, relation `has`; `fullText` options and `orderByTextScore`.
- Query options: nested `include`, `includeAll`, `get`, `findAndCount`, `raw(exclude:)`, `hint`, `comment`, `readPreference`.
- Writes: custom object ids, trigger `context`, map `setKey`/`incrementKey`/`unsetKey`, typed values inside map fields; batches go 20 items to a request.
- Auth: `requestEmailVerification`, `verifyPassword`, `linkWith`, `unlink`, `updatePassword`, `session()`; `ParseClient.installationId`.
- Files: `metadata`, `tags`, `onProgress`, `cancel`, `downloadFile`. Live queries: `watch`.
- Opt-in retries (`attempts`) and idempotent writes (`idempotency`); an `X-Parse-Client-Version` header.

## 0.2.0

- Breaking: `BatchResult` is renamed `Result`, now shared by batch and `tryFind`.
- `Auth.logInWith(provider, authData)` for third-party login such as Google or Apple.
- `ParseClient.config()` returns the client-visible params of `GET /config`.
- `ListField.containsAny` matches a row whose list holds any of the values.
- `Query.tryFind()` returns one `Result` per row, so a row that does not decode is an `Err` carrying the row's id instead of failing the page.

## 0.1.0

- First release: wire codec, `ParseClient` and `Collection` CRUD with atomic update ops, typed queries, auth with a pluggable `SessionStore`, cloud functions, batch, file upload and live queries.
