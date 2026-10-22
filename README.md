# parse_next

A type-safe [Parse Server](https://parseplatform.org) SDK for Dart and Flutter. Models are plain immutable classes, a code generator writes their query fields and update ops, and the compiler rejects a wrong field or type before a request is sent. Pure Dart: it runs in Flutter, on the web and on the server, and depends only on `http` and `web_socket_channel`.

Tested against parse-server 9.9.0 on MongoDB and on Postgres.

| Package | What it is |
|---|---|
| [`parse_next`](packages/parse_next) | The SDK. Start with [its README](packages/parse_next/README.md). |
| [`parse_next_generator`](packages/parse_next_generator) | The `build_runner` generator, a dev dependency. |
| `parse_next_it` | Integration tests against real servers; not published. |

## What it supports

Grouped as the [Parse JavaScript guide](https://docs.parseplatform.org/js/guide/) is, so it can be read side by side with it. Checked items are in the SDK and tested, most against both databases in `parse_next_it` and the rest, such as the distance helpers, in unit tests. Unchecked items are not in the SDK, with the reason.

The master key is for Dart code that runs on a server; an app must not hold it.

### Getting started
- [x] Connect with server URL, app id and client key — `ParseClient(server:, appId:, clientKey:)`
- [x] An `http.Client` of your own, a request timeout
- [x] One installation id per install — `ParseClient(installationId:)`
- [x] Retries, opt-in — `attempts` for reads; `idempotency` for writes, which uses the server's `idempotencyOptions`
- [x] Master key, for code on a server — `ParseClient(masterKey:)`, sent on every request and on the live query connection

### Objects
- [x] Typed classes — `@ParseClass('Post')` and the generator
- [x] Save a new object — `collection.create(value, acl:)`
- [x] Your own object id — `create(value, id:)`, with the server's `allowCustomObjectId`
- [x] Cloud Code context — `context:` on `create`, `update`, `replace`, `delete` and `batch.send`
- [x] Retrieve by id — `collection.get(id)`, or `query().include(...).get(id)`
- [x] Update with Parse ops, applied atomically — `collection.update(id, (o) => [...])`
- [x] The object as the server has it after an update, trigger changes included — `UpdateResult.applyTo(doc)`
- [x] Overwrite every field — `collection.replace(id, value)`
- [x] Counters — `o.likes.increment(n)`, negative to decrement
- [x] Arrays — `set`, `add`, `addUnique`, `remove`
- [x] One key of an object field — `o.meta.setKey`, `incrementKey`, `unsetKey`: one top-level key, once per map in an update
- [x] Remove a field — `o.field.unset()`
- [x] Delete — `collection.delete(id)`
- [x] Several writes in one request — `client.batch()`, 20 to a request, or atomically with `send(transaction: true)`
- [ ] Save nested new objects in one call — save each, then point to it
- [ ] Save offline (`saveEventually`, `destroyEventually`) — no local store

### Data types
- [x] String, Number (`int`, `double`, `num`), Boolean, Date, enum (stored by name)
- [x] Array of String, Number or Boolean, and of Pointers
- [x] Object — `Map<String, Object?>`, holding `DateTime`, `GeoPoint`, `Polygon` and `ParseFile` at any depth
- [x] Pointer, Relation, File, GeoPoint, Polygon, Bytes (`Uint8List`)
- [x] Null and absent — a nullable field
- [ ] An Array of Dates, GeoPoints, Files or Objects as a typed field — use a `Map` field or a pointer list

### Queries
- [x] Find, first, count, find and count in one request — `find`, `first`, `count`, `findAndCount`
- [x] `equalTo`, `notEqualTo`, `lessThan(OrEqualTo)`, `greaterThan(OrEqualTo)` — `eq`, `ne`, `lt`, `lte`, `gt`, `gte`
- [x] `containedIn`, `notContainedIn` — `oneOf`, `noneOf`
- [x] `exists`, `doesNotExist` — `exists()`, `exists(false)`
- [x] `limit`, `skip`, `ascending`, `descending` over several keys — `limit`, `skip`, `orderBy(f.x.asc)`
- [x] Every match, page by page (`each`, `eachBatch`, `findAll`) — `stream()`
- [x] Rows that fail to decode, without failing the page — `tryFind()`
- [x] `select`, `exclude` — partial: `raw(keys:, exclude:)` returns untyped rows, since a partial object does not decode into a model with required fields
- [x] Conditions inside an Object field — `f.meta.at('a.b')`
- [x] `hint`, `comment`, `readPreference`
- [x] More than ~1,000 ids in a condition — queries are sent in the body, never in the URL
- [x] `explain`, `aggregate`, `distinct` — `query.explain()`, `collection.aggregate(pipeline)`, `query.distinct((f) => f.x)`, undecoded; need the master key
- [ ] Local vs. server data — no local store

#### Queries on arrays
- [x] `equalTo` on an array, `containsAll`, `containedIn` on an array — `contains`, `containsAll`, `containsAny`
- [x] `containedBy`, `containsAllStartingWith`

#### Queries on strings
- [x] `startsWith`, `endsWith`, `contains` (escaped), `matches` (regex, case-insensitive)
- [x] Full-text search with language, case and diacritic options — `fullText`
- [x] Sort by text score — `orderByTextScore()`

#### Relational queries
- [x] On a pointer: `equalTo`, `notEqualTo`, `containedIn`, `notContainedIn` — `eq`, `ne`, `oneOf`, `noneOf`, `isId`
- [x] `matchesQuery`, `doesNotMatchQuery`
- [x] `matchesKeyInQuery`, `doesNotMatchKeyInQuery` — `matchesKey`, `notMatchesKey`
- [x] Objects related through a Relation — `relationField.of(ownerId)`
- [x] Objects whose Relation holds a member — `relationField.has(pointer)`
- [x] `include`, nested includes, `includeAll` — `include((f) => f.author.then((a) => a.team))`

#### Compound queries
- [x] OR, AND, NOR — `|`, `&`, `~`

### Live queries
- [x] Subscribe — `query.live()`, a `Stream`
- [x] create, update, enter, leave and delete events — `Created`, `Updated`, `Entered`, `Left`, `Deleted`
- [x] Open and close — `Subscribed` after every (re)connect, `Disconnected` when the connection drops
- [x] Errors — a server error for the subscription ends the stream with its `ParseException`
- [x] Unsubscribe — cancel the stream; close the socket — `client.close()`
- [x] A LiveQuery server on another URL — `ParseClient(liveQueryServer:)`
- [x] Reconnect — automatic, with backoff; never ends the stream
- [x] Session token — the session at the time of listening
- [x] Only updates to some fields (`watch`) — `live(watch: (f) => [...])`
- [ ] Only some fields in events (`keys`) — a partial object does not decode into the model

### Users
- [x] Sign up, log in, log out — `auth.signUp`, `logIn`, `logOut`
- [x] Current user — `auth.current()`, `auth.me()`, and `auth.changes`
- [x] Set the current user from a session token — `auth.become`
- [x] Keep the session between runs — your `SessionStore`, such as secure storage, which covers encrypting it
- [x] Verify emails — `auth.requestEmailVerification`, and `emailVerified` as a model field
- [x] Reset password — `auth.requestPasswordReset`
- [x] Change password, keeping this session — `auth.updatePassword`
- [x] Check a password without logging in — `auth.verifyPassword`
- [x] Query users and point to them — a `_User` model in a `collection`
- [x] Log in with a provider (Google, Apple, Facebook, anonymous, ...) — `auth.logInWith(provider, authData)`
- [x] Link and unlink a provider — `auth.linkWith`, `auth.unlink`
- [ ] Provider SDK modules that fetch `authData` for you — get it from the provider's own package

### Sessions
- [x] The current session's properties — `auth.session()`: id, `expiresAt`, `installationId`, `createdWith`
- [x] Invalid session token — `InvalidSession` (209); the stored session is cleared

### Roles
- [x] Roles as a model — `@ParseClass('_Role')` with `users` and `roles` relations
- [x] Role-based access — `Acl().withRole(name)`
- [x] Role hierarchy — the `roles` relation

### Files
- [x] Upload — `client.uploadFile(bytes, name:, contentType:)`, with progress and cancel
- [x] Store in an object field — `ParseFile`
- [x] Download — `client.downloadFile(file)`
- [x] Metadata and tags — `uploadFile(metadata:, tags:)`
- [x] Delete — `client.deleteFile(file)`; needs the master key

### GeoPoints
- [x] `GeoPoint`, `Polygon`, distances — `radiansTo`, `kilometersTo`, `milesTo`, `Polygon.containsPoint`
- [x] `near`, with a maximum distance — `near(point, maxKm:)`
- [x] `withinKilometers` without sorting — `withinKm`; miles and radians: convert
- [x] `withinGeoBox`, `withinPolygon`, `polygonContains` — `withinBox`, `withinPolygon`, `containsPoint`
- [ ] The device's location (`GeoPoint.current`) — use a location package

### Local datastore
- [ ] Pinning, local queries, cached results — not supported

### Push notifications
- [x] An installation id on every request
- [x] Send a push to channels or to an `_Installation` query — `client.push(data, channels:)`, `push(data, where:)`; needs the master key and a push adapter on the server
- [x] An `_Installation` type — model it with `@ParseClass('_Installation')`
- [ ] Scheduled pushes and expiry (`push_time`, `expiration_time`) — not supported

### Config
- [x] Retrieve config — `client.config()`; `masterKeyOnly` params are sent only with the master key
- [x] Save config — `client.saveConfig(params, masterKeyOnly:)`; needs the master key
- [ ] A cached current config — keep the result yourself

### Analytics
- [ ] Custom events — not supported

### Cloud Code
- [x] Call functions with typed parameters and results — `@ParseFunctions`
- [x] Start a job — `client.startJob(name, params)`, returning its `_JobStatus` id; needs the master key

### Schema
- [x] Schemas, indexes, class-level permissions, purge — `client.schemas()`, `client.schema(name)` with `get`, `create`, `update`, `delete`, `purge`; untyped; need the master key

### Relations
- [x] One-to-one and one-to-many — `Pointer<T>`
- [x] Many-to-many — `Relation<T>`, an array of pointers, or a join class

### Errors
- [x] Every failure is a sealed `ParseException`: `ObjectNotFound`, `DuplicateValue`, `ScriptFailed`, `UsernameTaken`, `EmailTaken`, `InvalidCredentials`, `InvalidSession`, `Unauthorized`, `NetworkError`, `DecodeError`, `OtherParseError` with the code
- [x] Values the server would store wrongly are rejected before sending — `ArgumentError`

### Security
- [x] Access control lists — `Acl`: public, user and role read and write

Class-level permissions, pointer permissions, cloud-code validation and rate limits are server configuration; the SDK reports their errors.

### Data
Storage, the data browser, import and export are server and dashboard features.

## Development

The integration tests need Docker: Compose starts parse-server 9.9.0 on MongoDB (port 1337) and on Postgres (port 1338).

```sh
tool/ci.sh
```

runs every check: dependency and code rules, generated code and fixtures, analyze, format, unit tests (VM, and Chrome for the platform-dependent ones), generator tests, then the integration and live-query suites. [PLAN.md](PLAN.md) records the design, the rules and every server behavior the SDK relies on.

## License

Apache 2.0.
