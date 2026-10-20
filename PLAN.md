# parse_next — build plan

A type-safe Parse SDK for Dart and Flutter, built on code generation. No reflection, no string keys in app code, nothing implicit.

Package names `parse_next` and `parse_next_generator` were unclaimed on pub.dev as of 2026-10-20. Claim them before Phase 10.

## Design summary

- Models are plain immutable Dart classes annotated with `@ParseClass('Name')`. They have no base class and no metadata fields.
- `Doc<T>` carries `id`, `createdAt`, `updatedAt` and `acl` around the model. An unsaved object has no id, so nothing can point to it.
- `Pointer<T>` holds an `id` plus `Doc<T>? loaded`, which is non-null only when the query used `include()`.
- For each class, the generator emits:
  - `XFields`: typed query fields. Each field type only offers the constraints Parse supports for it.
  - `XOps`: typed update ops. Only the ops valid for the field exist (for example, `unset` only on nullable fields).
  - `$XSchema`: the class name, `encode`, `decode`, fields and ops.
- Writes are explicit:
  - `update(id, ops)` sends Parse ops (`Increment`, `AddUnique`, `Delete`, …), which the server applies atomically.
  - `replace(id, obj)` does a full PUT, and the last write wins.
  - There is no dirty tracking and no `save()`.
- Typed queries always return full objects. `raw(keys:)` returns `List<Json>` for projections.
- `ParseException` is sealed, and `DecodeError` fires where data enters the app when a server row doesn't match the model.

## Scope of v1

**In scope:** wire codec, transport, CRUD with ops, typed queries, the generator, auth, cloud functions, batch, files, live queries.

**Out of scope:** dirty tracking and `save()`, typed projections, local datastore and offline support, master key and admin APIs, push, the schema-pull CLI, nested embedded classes. Each needs its own plan; none gets added quietly.

## Rules for the whole repo

| # | Rule | Checked by |
|---|---|---|
| G1 | `parse_next` depends only on `http` and `web_socket_channel`. No Flutter. | CI checks the `dependencies:` block against an allowlist |
| G2 | No `dynamic` in `lib/`. JSON is `Object?` / `Json`. | `grep -rn '\bdynamic\b' packages/*/lib` finds nothing |
| G3 | `strict-casts`, `strict-inference`, `strict-raw-types` | `dart analyze --fatal-infos` is clean |
| G4 | Formatted | `dart format --set-exit-if-changed .` |
| G5 | Runs on VM and web | unit tests run with `-p vm,chrome` |
| G6 | No silent retries, no hidden state | `MockClient` tests assert exact request counts |
| G7 | Every Parse behavior the SDK depends on is proved against a real server | integration suite |
| G8 | The type-safety promises are tested | compile-fail suite |
| G9 | No skipped test without a reason string | CI fails on `skip: true` |

Pinned at the start and changed only on purpose:
- the Dart SDK lower bound: **3.8.0**, the oldest SDK the code can compile on. CI runs one pinned SDK, **3.13.5**, with the lockfile enforced
- the `parse-server` image: **`parseplatform/parse-server:9.10.5`**, the latest release; older servers are not tested
- Mongo and Postgres versions: **`mongo:8.0.34`**, **`postgis/postgis:18-3.6`** pinned by digest

## How things get verified

1. **Golden JSON tests.** The wire format is compared exactly against real server responses captured in Phase 0. Fixtures are never written by hand.
2. **Integration tests.** They run against `parse-server` in Docker Compose, on both Mongo and Postgres. An operation one database doesn't support is skipped there with a reason and documented.
3. **Oracle query tests.** The database is seeded with 200 deterministic objects (`Random(42)`). Every query result must equal the same filter applied to the seed list in plain Dart.
4. **Compile-fail suite.** Each `test/compile_fail/*.dart` file starts with the analyzer error code it must produce. A test runs `dart analyze --format=machine` on each file and checks the code. The folder is excluded from the normal analyze run.
5. **Generator golden tests.** `build_test`'s `testBuilder` must produce byte-identical output.

## Server behavior found so far (parse-server 9.10.5)

Later phases must follow these:

| Behavior | Affects |
|---|---|
| Mongo returns a field set to null as `"x": null`; Postgres leaves it out. Decode treats both as absent. | Phase 1 |
| Unauthorized is 403 `{"error":"unauthorized"}` with no `code` and **no `Content-Type`**. Parse error bodies regardless of headers. | Phase 2 |
| 101 is HTTP 404, both for a missing id and for an ACL denial. 137, 141 and 209 are HTTP 400. | Phase 2, 3 |
| A cloud `throw new Error(msg)` returns `{"code":141,"error":msg}` unsanitized. | Phase 7 |
| Increment, Add, AddUnique and Remove return the new field value; Delete, AddRelation and RemoveRelation return only `updatedAt`. | Phase 3 |
| On Postgres, AddUnique reorders the array (`SELECT DISTINCT` in `add-unique.sql`). After AddUnique/Remove, compare arrays as sets on Postgres. | Phase 3, 4 |
| On Mongo, writing `null` to a Polygon field (in a create or a PUT) makes every later GET and DELETE of that object return 500 (`MongoTransform.js` reads `.coordinates` before checking for null). A `Delete` op is fine, so the SDK never sends null: create leaves null fields out, and `replace` and `unset` send `Delete`. | Phase 3 |
| A class allows one GeoPoint field, on both databases (`validateObject` and `validateSchemaData` in `SchemaController.js`). | Phase 3, 5 |
| On Postgres, an update or replace that writes a Bytes value fails with 119 `Postgres doesn't support update` (`updateObjectsByQuery` in `PostgresStorageAdapter.js`); creating one and `Delete` work. | Phase 3, 8 |
| On Postgres, a `Delete` of a field the class schema lacks is a 500 (`column … does not exist`); Mongo accepts it. `replace` sends a `Delete` for every null field, so every field must be in the schema. | Phase 3 |
| Empty Bytes are rejected with 111 `This is not a valid Bytes`: `getObjectType` in `SchemaController.js` tests `base64` for truthiness. | Phase 3 |
| `AddRelation`/`RemoveRelation` with an empty `objects` list is a 500 (`getObjectType` reads `objects[0].className`). `RelationOps` rejects an empty list with `ArgumentError`. | Phase 3 |
| Clients cannot create classes (`allowClientClassCreation` defaults to false; 119 `Permission denied`) but can add fields to an existing one. Tests create schemas with the master key. | Phase 3 |
| New users have no public read (`enforcePrivateUsers` defaults to true), so an anonymous GET of a `_User` is 101. | Phase 3, 6 |
| A create response carries the fields a `beforeSave` trigger changed, and a field the trigger unset as `{"__op":"Delete"}` (`_updateResponseWithData` in `RestWrite.js`). | Phase 3 |
| Polygons come back closed: the server appends the first point. | Phase 1, 3 |
| `2.0` comes back as `2`. | Phase 1 |
| A unique index treats a missing field as null on Mongo (only one object may lack it) but not on Postgres. | Phase 3 |
| File URLs follow the request host. Public file upload is off by default. | Phase 8 |
| A Polygon needs at least 3 distinct vertices, or the write fails (`PolygonCoder.JSONToDatabase` in `MongoTransform.js`). `Polygon` checks this at construction. | Phase 1, 3 |
| A create returns only `objectId` and `createdAt`, not `updatedAt`; a GET straight after has both. | Phase 3 |
| The file upload response is `{name, url}` without `__type`, unlike a File field. | Phase 8 |
| An uncaught internal error is 500 `{"code":1,"message":…}`: the text is under `message`, not `error` (`handleParseErrors` in `middlewares.js`). Any other 403 without a `code`, such as `unauthorized: master key is required`, is also sent with `res.end` and no `Content-Type`; every 403 without a code maps to `Unauthorized`. | Phase 2 |
| After that uncaught 500, `handleParseErrors` calls `next(err)` and Express's `finalhandler` destroys the socket. The next request on the same pooled keep-alive connection fails with `Connection closed before full header was received` (a `NetworkError`), and that request never reaches the server. Only this uncaught-error path does it; the `"An internal server error occurred"` 500 keeps the socket. Decision: document it on `NetworkError` and keep keep-alive, since turning it off would cost a new TCP/TLS connection per request. The one expected path to this 500, a failed transactional batch, is sent with `Connection: close`, so the next call is unaffected. | Phase 2 |
| A date constraint with a plain ISO string matches nothing on Mongo but is cast to a date and matches on Postgres. Queries always send `{"__type":"Date"}`. | Phase 4 |
| `$nin` never matches an absent field on Postgres (`NOT IN`), but does on Mongo. `$in: []` matches absent fields on Postgres (`IS NULL`) and nothing on Mongo, so `oneOf([])` throws `ArgumentError` (`buildWhereClause` in `PostgresStorageAdapter.js`). | Phase 4 |
| Ascending sorts put absent values first on Mongo and last on Postgres. Strings compare and sort by the database collation: binary on Mongo, `en_US.utf8` on Postgres (`"Banana" > "b"` there). The oracle uses lowercase a–f names, where both orders agree. | Phase 4 |
| Equality on an array field (`{"tags":"a"}`) is a 500 on Postgres, so `contains` sends `$all`. | Phase 4 |
| Only the Mongo adapter reads `$maxDistanceInKilometers`; Postgres reads only `$maxDistance` in radians, so `near` sends radians. In `$geoWithin.$polygon`, both adapters read a Polygon value's coordinates as `[longitude, latitude]`, so `withinPolygon` sends GeoPoints. | Phase 4 |
| On Mongo, `$nearSphere` inside `$or` (`geo $near must be top-level expr`), `$text` inside `$or`, and `$text` with `$nearSphere` in one query (`text and geoNear not allowed in same query`) are all 500s. Postgres accepts all three. | Phase 4 |
| On Mongo, only `find` creates the text index (`createTextIndexesIfNeeded` in `MongoStorageAdapter.js`), so a `$text` count before the first find is a 500 (`text index required`). A collection has one text index, and `$text` searches it whatever the field. On Postgres a multi-word `$text` term is a 500 (`to_tsquery` syntax). | Phase 4 |
| `X-Parse-Revocable-Session` is read nowhere (it appears only in the CORS allow list in `middlewares.js`), and every token from sign-up, login and `/users/me` is an `r:` revocable token. Sign-up does not send the header. | Phase 6 |
| A wrong username or password on `/login` is 101, HTTP 404, `Invalid username/password.` (`UsersRouter.js`), the same code as a missing object, so `InvalidCredentials` is mapped only for `/login`. A taken username is 202 and a taken email 203, both HTTP 400. | Phase 6 |
| Any request carrying an invalid session token fails with 209 before routing, except `/login`, which drops the token (`handleParseHeaders` in `middlewares.js`). Sign-up, login, become and password reset never send the stored token. `/logout` with a revoked token is also 209. | Phase 6 |
| The sign-up response is only `objectId`, `createdAt` and `sessionToken`: no `ACL`, no `updatedAt`. Login and `/users/me` return the whole user with its `ACL` and `sessionToken`. | Phase 6 |
| Password reset fails with 1 unless the server has an email adapter, `appName` and `publicServerURL` (`_throwOnBadEmailConfig` in `UsersRouter.js`). An unknown email gets the same `{}` as a known one while `passwordPolicy.resetPasswordSuccessOnInvalidEmail` is unset (default true). Once `publicServerURL` is set it also replaces the request host in file URLs (`mount` in `Config.js`), so Compose sets each server's own host URL. | Phase 6, 8 |
| Deleting a `_Session` with the master key also evicts its token from the server's user cache (`del` in `rest.js`), so the revoked token fails on its very next request. | Phase 6 |
| Function params become a JS `Date`, `Parse.File` and `Parse.Object` for Date, File and Pointer; GeoPoint, Polygon and Bytes stay plain JSON (`parseParams` in `FunctionsRouter.js`). The result goes through `Parse._encode`: a fetched `Parse.Object` is `{"__type":"Object","className",…}` with its fields inline and `createdAt`/`updatedAt` as plain ISO strings, an unfetched one a Pointer, and every other value is encoded as in a field. `undefined` leaves `result` out of the response; `null` sends `"result": null`. | Phase 7 |
| Returning a File param from cloud code kills the server process: the SDK sends a File without `url`, and `Parse._encode` throws `Tried to encode an unsaved file.` inside `success` in `FunctionsRouter.js`, where nothing catches it. The fixture functions return `file.toJSON()` instead. | Phase 7 |
| A thrown `Parse.Error` keeps its code (`resolveError` in `triggers.js`), with the usual HTTP status (101 is 404, 1 is 500, the rest 400). A cloud `throw new Parse.Error(209, …)` therefore clears the caller's stored session. An unknown function is 141 `Invalid function: "name"`. | Phase 7 |
| Returning `request.user` includes the caller's `sessionToken` in the result; decoding into a model drops it. | Phase 7 |
| A batch response is a top-level JSON array, one `{"success":…}` or `{"error":{code,error}}` per item. A create item's `success` carries `beforeSave` changes like a plain create. An empty `requests` list is 200 `[]`. | Phase 8 |
| A transactional batch with a failing item is 500 `{"code":1,"message":"Internal server error."}`; the item errors appear only in the server log (`handleBatch` in `batch.js`). On a standalone Mongo every transactional batch fails this way, with item error 20. | Phase 8 |
| An upload's stored name keeps a recognized extension and the type follows it, whatever `Content-Type` was sent; a name without an extension gets the sent type's extension (`createFile` in `FilesController.js`), and no `Content-Type` counts as `text/plain` (the `Parse.File` base64 default). Downloads set `Content-Type` from the name's extension (`mime.getType` in `getHandler` in `FilesRouter.js`), and an unknown extension is served as `Content-Type: false`. | Phase 8 |
| On Postgres, `$ne`, `$in`, `$nin` and `$eq` with a Date are 500s (`invalid input syntax for type timestamp`), on Date fields and on `createdAt`/`updatedAt`: `buildWhereClause` in `PostgresStorageAdapter.js` passes the `{"__type":"Date"}` object unconverted. Plain equality, `$gt`/`$gte`/`$lt`/`$lte` and `$exists` work on both databases. `DateField` therefore offers only `eq`, the four ranges, `exists`, `asc` and `desc`. | Phase 4 |
| LiveQuery matches in JavaScript, not in the database (`matchesKeyConstraints` in `QueryTools.js`). `$text`, `$inQuery` and `$relatedTo` never match; `createdAt`/`updatedAt` arrive as ISO strings and are compared with a decoded Date, so ranges always match and equality never does; `$in`/`$nin` with Dates and `$all` with Pointers compare by identity; an empty `$all` matches any list. An absent field passes every range check, a `$regex` is tested against the string `"undefined"`, and `$geoWithin` throws, which drops the event. None of these is an error. `live()` rejects the first group with `ArgumentError` and puts `$exists: true` first in range, regex and `$geoWithin` constraints. | Phase 9 |
| LiveQuery errors are `{"op":"error","error","code","reconnect","requestId"}`. A subscribe fails only for an invalid regex or too-deep query (102), a CLP denial (119) or a `_Session` subscription without a user (209). An invalid session token is not an error: the subscription is treated as anonymous (`getAuthForSessionToken` in `ParseLiveQueryServer.ts`). An `unsubscribe` for a subscription the server has not registered yet is an error with code 2 and no `requestId`. | Phase 9 |
| A subscribe without `sessionToken` is matched with the token sent on `connect` (`_matchesACL` in `ParseLiveQueryServer.ts`), so a subscription made after logout would see the previous user's objects. The SDK sends no token on `connect`, only on each `subscribe`. | Phase 9 |
| Only classes in `liveQuery.classNames` publish changes; a subscription to any other class is accepted and never receives an event. The server pings every 10 s and drops a socket that missed the last pong (`ParseWebSocketServer.js`); `dart:io` and browsers answer pings, so the SDK sends no keepalive. | Phase 9 |
| `POST /users` with `authData` answers a new user with 201 and only `objectId`, `createdAt`, a generated `username`, `sessionToken` and `authDataResponse` (no `updatedAt`, no `ACL`), and an existing one with 200 and the whole user, including `authData`. With a session token the request links the `authData` to that user instead of logging in (`handleAuthData` in `RestWrite.js`), so `logInWith` never sends the stored token. | Phase 6 |
| A rejected `authData` keeps the adapter's `Parse.Error` code (`handleAuthDataValidation` in `Auth.js`); the built-in adapters reject with 101, HTTP 404 (93 of their throws in `src/Adapters/Auth/`), so `logInWith` maps 101 to `InvalidCredentials`. A provider the server does not have is 252 `This authentication method is unsupported.`, HTTP 400, and stays `OtherParseError`; an adapter that throws a non-Parse error is 141. | Phase 6 |
| `GET /config` without the master key leaves out every param marked `masterKeyOnly`, and also returns a `masterKeyOnly` map of the other keys (`getGlobalConfig` in `GlobalConfigRouter.js`). `PUT /config` merges into the stored params. | Phase 7 |
| `$in` on an Array field matches a list holding any of the values on both databases: Postgres compiles it to `array_contains` (`buildWhereClause` in `PostgresStorageAdapter.js`, `sql/array/contains.sql`), which is `STRICT`, so an absent list never matches, as on Mongo; pointer lists work on both. `$in: []` is `IS NULL` on Postgres and matches only absent lists, so `containsAny([])` throws `ArgumentError`. LiveQuery's `contains` in `QueryTools.js` compares pointers by `className` and `objectId`, so `containsAny` on a pointer list matches live as in a find. | Phase 4, 9 |
| Upload errors are HTTP 400: an anonymous upload is 130 `File upload by public is disabled.`, an empty body 130 `Invalid file upload.`, a name outside `[_a-zA-Z0-9][a-zA-Z0-9@. ~_-]*` or over 128 characters 122 (`validateFilename` in `FilesAdapter.js`). | Phase 8 |

## Repo layout

```
parse_next/                     pub workspace (Dart ≥ 3.8)
  packages/parse_next/            runtime: client, codec, query/ops DSL, auth, live query, annotations
  packages/parse_next_generator/  build_runner builder, dev_dependency only
  packages/parse_next_it/         integration tests, models, cloud/main.js; never published
  docker/compose.yaml             parse-server, mongo, postgres, live query enabled
  .github/workflows/ci.yaml
```

---

## Phase 0: Skeleton and CI

**Build**
- the workspace, empty packages and `analysis_options.yaml`
- the Compose stack and the CI workflow
- a `capture` script that runs real REST calls against the server and saves the responses to `packages/parse_next/test/fixtures/`

**Verify**
- CI runs analyze, format, unit tests (VM and Chrome) and integration tests, and all are green with zero tests.
- `GET /parse/health` returns OK on both databases.
- Fixtures exist for:
  - create, get and query on every field type
  - every op
  - each of these errors: 101, 137, 141, 209, and unauthorized

**Exit:** CI is green and the fixtures are committed.

## Phase 1: Wire codec

**Build:** `Json` (an extension type), and codecs for:
- Date
- `Pointer<T>`
- `ParseFile`
- `GeoPoint`
- `Polygon`
- Bytes
- `Acl`
- the `Relation` marker
- the `Doc<T>` envelope (`objectId`, `createdAt`, `updatedAt`, `ACL`)

**Rules**
- Pure functions with no IO.
- Numbers are always read as `num` and then converted. On the VM `jsonDecode('3') is double` is false; on web `1.0 is int` is true. Both must decode the same way.
- `createdAt`/`updatedAt` arrive as plain ISO strings, while Date fields arrive as `{"__type":"Date"}`. Handle both, always as UTC with millisecond precision.
- `GeoPoint` rejects lat outside ±90 and lng outside ±180 when it's constructed (`ArgumentError`).
- `Acl` handles `*`, user ids and the `role:` prefix.

**Verify**
- For every fixture, decoding gives the expected value and encoding gives back the exact fixture.
- Edge cases: Unicode strings, empty arrays, missing optional fields, an unknown `__type` (raises `DecodeError`).
- Everything passes on VM and Chrome.

**Exit:** all codec golden tests are green on both platforms.

## Phase 2: Transport and errors

**Build**
- `ParseClient` config: server, appId, clientKey, an injected `http.Client`, a timeout
- header handling
- mapping every failure to a `ParseException`

**Rules**
- No retries of any kind (G6).
- Error mapping:
  - a non-2xx response with `{code, error}` becomes a typed subclass
  - a 403 `{"error":"unauthorized"}` with no `code` (parse-server does send this) becomes `Unauthorized`
  - a body that isn't JSON becomes `OtherParseError` with the HTTP status
  - socket errors and timeouts become `NetworkError`

**Verify**
- `MockClient` tests check:
  - exact headers for every combination of client key and session token
  - each captured error fixture maps to the right subclass
  - a timeout becomes `NetworkError`
  - exactly one request is sent per call
- The integration tests for a wrong app id (`Unauthorized`) and an unreachable host (`NetworkError`) moved to Phase 3: there is no public call to make until `Collection` exists, and the request function stays private.

**Exit:** every error fixture is covered, and the `switch` over `ParseException` is exhaustive with no `default`.

## Phase 3: Hand-written schema and Collection CRUD

**Build**
- `$PostSchema` and `$UserSchema` written by hand in `parse_next_it`, covering every supported field type
- `Collection` with `create`, `get`, `update(ops)`, `replace` and `delete`

**Supported field types** (anything else becomes a build error in Phase 5):
- `String`, `int`, `double`, `num`, `bool`, `DateTime`
- enums, stored by `name`; an unknown value raises `DecodeError`
- `List<primitive>`
- `Map<String, Object?>`
- `Pointer<T>` and `List<Pointer<T>>`
- `Relation<T>`
- `ParseFile`, `GeoPoint`, `Polygon`, `Uint8List`
- nullable versions of all of the above

**Verify (integration)**
- Round trip: `get(create(x)).data == x` for every field type.
- Ops:
  - 20 increments from 20 separate clients in parallel leave `likes == 20`, which proves the op is atomic
  - `addUnique` is idempotent
  - `remove` removes, and `unset` makes the field absent
  - relation add and remove are confirmed with a `$relatedTo` query
- `replace` overwrites every field.
  - Not possible for Post on Postgres, which rejects any update that writes a Bytes value (see the table above), and Post has a required Bytes field. That test is skipped on Postgres with the reason; `replace` sending nulls as `Delete` is proved there on Note, which has no Bytes field.
- A missing id raises `ObjectNotFound`.
- A wrong app id raises `Unauthorized`, and an unreachable host raises `NetworkError` (moved from Phase 2).
- An ACL denial: user B updating user A's object gets **101 `ObjectNotFound`**, not a 403. The test locks in that server behavior.
- Compile-fail: `unset` on a non-nullable field, `increment` on a String or List, and passing a value of the wrong type to `set`.

**Exit:** CRUD and op tests are green on both databases.

## Phase 4: Query DSL

**Build**
- `where` with every constraint the field types offer, plus `&` and `|`
- `include`, `orderBy`, `limit`, `skip`, `count`, `first`
- `stream()` with objectId-cursor pagination
- `raw(keys:)`
- `ListField.containsAny` (`$in`), proved by the query oracle and the live oracle on both databases, pointer lists included
- `tryFind()`: `find` with one `Result` per row, where a row that does not decode is `Err(DecodeError)` carrying the row's objectId in `DecodeError.id`

**Rules**
- Date constraints always send `{"__type":"Date"}`.
- `&` merges into a single object when the keys don't collide, and uses `$and` otherwise. JSON output is deterministic, with keys in a stable order.

**Verify**
- Unit tests: each constraint compiles to exact golden `where` JSON.
- Oracle tests: every constraint, every combination of two with `&` and `|`, and every sort order match the Dart filter on the 200-object seed.
- `stream()` over 1,050 objects (past the default limit of 100) returns no duplicates and no gaps.
- `include`: `loaded` is non-null when included and null otherwise.
- Date regression: `createdAt.gt(t)` returns the right rows. A raw-JSON test with a plain ISO string returns zero rows, which documents why the encoding matters.
  - Zero rows only on Mongo. Postgres casts the string and matches, so the test asserts every row there (see the table above).
- Compile-fail: `gt` with the wrong type, `startsWith` on a List, `include` on a non-pointer field, `matchesQuery` with a query on a different class.

**Exit:** the oracle suite is green on both databases.

## Phase 5: Generator

**Build:** a `parse_next_generator` builder that emits `.parse.dart` files with `XFields`, `XOps` and `$XSchema`.

**Rules**
- The output matches the Phase 3 hand-written schemas **byte for byte**.
- Generated code passes the same strict analysis (G3).
- Input rules: a named-parameter unnamed constructor only, and `@ParseKey` values must be unique.
- Invalid input fails the build with a message that points at the offending element.

**Verify**
- `testBuilder` golden tests for Post and User match the Phase 3 files.
- Error tests, one per rule:
  - an unsupported type
  - a `Pointer` to a class that isn't a `@ParseClass`
  - a duplicate key
  - positional constructor parameters
  - no unnamed constructor
- **Delete the hand-written schemas and switch `parse_next_it` to generated ones. The full Phase 3 and 4 suites must pass unchanged.**
- A freezed model in `parse_next_it` round-trips correctly.

**Exit:** the hand-written schemas are deleted and everything is green.

## Phase 6: Auth

**Build**
- `Auth<U>` with `signUp`, `logIn`, `logOut`, `become(token)`, `requestPasswordReset`, `current` and `changes`
- `logInWith(provider, authData)`: third-party login through `POST /users`, on the same session path as `logIn`; no linking or unlinking. Covered by golden tests on fixtures captured with the built-in `anonymous` provider, which needs no server config
- a `SessionStore` interface with an in-memory implementation in core

**Rules**
- The token lives only in `SessionStore` and never in a model.
- Sign-up sends `X-Parse-Revocable-Session: 1`.
  - Not sent: parse-server reads the header nowhere and every session is already revocable (see the table above).
- A 209 error clears the store, emits `null` on `changes`, and is still thrown to the caller. Nothing is swallowed.

**Verify (integration)**
- The full lifecycle: sign up, log in, `current`, log out.
- A second `ParseClient` built with the same store is already logged in.
- A session revoked by another client makes the next call throw `InvalidSession`, and `current` becomes null.
- Phase 3's ACL tests are switched to real logged-in users.

**Exit:** all auth tests are green.

## Phase 7: Cloud functions

**Build**
- a generator for `@ParseFunctions` abstract classes
- `ParseClient.config()`: the `params` of `GET /config` as `Json`, covered by a golden test on a captured fixture

**Verify**
- `cloud/main.js` has one fixture function per supported parameter and return type, and every one round-trips.
- A function that throws gives `ScriptFailed` with its message.
- A return type that can't be encoded fails the build.
- Golden tests for the generated client.

**Exit:** every supported type is covered by a fixture function.

## Phase 8: Batch and files

**Build**
- `client.batch()` with typed handles: each added op returns a `BatchOp<R>` whose `result` is a sealed `Result<R>` (`Ok` or `Err`, shared with `Query.tryFind`) after one `send()`
- file upload returning a `ParseFile`

**Rules**
- Check parse-server's batch size limit and transaction behavior at the start of the phase and record them as constraints here.
- Batch is **not** transactional unless the call says so explicitly.
- Size limit: none by default. `requestComplexity.batchRequestLimit` defaults to `-1` (`RequestComplexityOptions` in `Options/Definitions.js`); a server that sets it rejects a longer batch as a whole with 107 unless the master key is used (`handleBatch` in `batch.js`). The SDK adds no client-side check. The JSON body is capped by `maxUploadSize`, 20 MB by default (`express.json` in `ParseServer.ts`).
- Items run concurrently, not in order (`Promise.all` over the requests in `handleBatch`); results come back in request order. Each item's `path` must include the mount path (`/parse/classes/Post`), or the batch fails with 107 `cannot route batch path`.
- Without `transaction`, each item applies or fails on its own, and the response is 200 with `{"success":…}` or `{"error":{code,error}}` per item. An item error has no HTTP status; the SDK gives it the status the server uses for that code on its own (1 is 500, 101 is 404, the rest 400).
- With `"transaction": true`, one failing item aborts the transaction and the server rejects with the item results as a plain object, not a `Parse.Error`, so the response is 500 `{"code":1,"message":"Internal server error."}` with no item results, and the socket is closed as for any uncaught error (see the table). `send(transaction: true)` throws `OtherParseError` code 1. Transient transaction errors (251) are retried up to 5 times by the server.
- Mongo transactions need a replica set: on a standalone server every transactional item fails with 20 `Transaction numbers are only allowed on a replica set member or mongos`, so every transactional batch is a 500. Compose runs Mongo as the single-node replica set `rs0`, initiated by its healthcheck. Postgres needs nothing (`createTransactionalSession` in `PostgresStorageAdapter.js`).
- `uploadFile` requires `contentType`: without a `Content-Type` the server treats the upload as `text/plain` and appends `.txt` to a name without an extension. The download's `Content-Type` comes from the stored name's extension, not from the uploaded type, so `contentType` is preserved only where it matches the extension (see the table).

**Verify**
- A batch with one failing item returns exactly one `Err` at the right index, while the others succeed.
- Uploading bytes and downloading from the URL gives identical bytes.
- `contentType` is preserved.

**Exit:** green on both databases.

## Phase 9: Live queries

**Build**
- `.live()` returning `Stream<LiveEvent<T>>`
- one multiplexed socket, with reconnect and resubscribe on exponential backoff
- cancelling the stream unsubscribes

**Rules**
- Events missed while disconnected are **not** replayed. The docs say this plainly.
- The session token is sent on connect.

**Verify (integration)**
- Each event type (create, enter, update, leave, delete) arrives exactly once and in order.
- When the connection drops (the server container is restarted), the client resubscribes and receives later events.
- After a cancel, a write produces no event within 2 s.
- An ACL-protected object is delivered only to the user allowed to read it.
- Compile-fail: a `switch` that misses an event type.

**Exit:** green, with the reconnect test stable across 20 consecutive CI runs.

## Phase 10: Release

**Verify**
- No Flutter device smoke test: `parse_next` is pure Dart with no plugins or platform channels, so a phone runs the same `dart:io` code paths the VM tests cover, and the web runs the code the Chrome tests cover.
- `dart pub publish --dry-run` is clean for `parse_next` and `parse_next_generator`.
- The public API is reviewed against this plan, and anything not listed here is removed.

**Exit:** tag `0.1.0`.

---

## What counts as "done", for every phase

1. All of G1–G9 pass in CI.
2. The phase's Verify list is complete, and every listed case exists as a test.
3. No test is skipped without a reason.
4. Only then does the next phase start.

## Defaults (change here if you disagree)

- Both Mongo and Postgres are required.
- Web is a supported platform.
- The master key stays out of v1.
- The batch limit is settled: there is no default limit (see the Phase 8 Rules).
- The lower bound is the oldest SDK whose language features and dependencies the code needs, and it is raised only when the code starts using something newer. It is not tested in CI, so as not to block apps on older Flutter. 3.8.0 is needed for null-aware map elements (`'key': ?value`), and by the generator's dependencies: it was raised from 3.6.0 in Phase 5. On 3.6, pub resolves `analyzer` 7, `source_gen` 2 and `build` 2, whose element API (`ParameterElement`, `parameters`) is the one analyzer 8 removed, while stable resolves `analyzer` 14; no one generator source compiles against both. Analyzer 8.0, the first with only the current API, needs 3.7, and `freezed` 3.2.1, the first to accept analyzer 8, needs 3.8. In `dart:3.8.0`, pub resolves `analyzer` 8.1.1, `source_gen` 4.2.0, `build` 4.0.7, `build_runner` 2.15.1, `build_test` 3.5.16, `freezed` 3.2.3, `lints` 6.1.0 and `test` 1.31.0. Language version 3.8 formats with the tall style, which the 3.8.0 and stable formatters agree on.
- parse-server 9.10.5 is the latest release. Mongo 8.0 and Postgres 18 with PostGIS 3.6 are versions parse-server's own CI tests. PostGIS publishes no patch-level tag and no arm64 image, so it is pinned by digest and runs under emulation on Apple Silicon.
- Fixtures are normalized so a rerun writes identical files: object ids, session tokens and file names become placeholders numbered by first appearance (`obj0000001`, `r:session0001`, `file0001_hello.txt`), every `createdAt`/`updatedAt` becomes `2000-01-01T00:00:00.000Z`, the server URL becomes `http://parse.test/parse`, and object keys are sorted. A fixture that differs between backends after this is kept as `<name>.mongo.json` and `<name>.postgres.json`.
