## 0.2.0

- Breaking: `BatchResult` is renamed `Result`, now shared by batch and `tryFind`.
- `Auth.logInWith(provider, authData)` for third-party login such as Google or Apple.
- `ParseClient.config()` returns the client-visible params of `GET /config`.
- `ListField.containsAny` matches a row whose list holds any of the values.
- `Query.tryFind()` returns one `Result` per row, so a row that does not decode is an `Err` carrying the row's id instead of failing the page.

## 0.1.0

- First release: wire codec, `ParseClient` and `Collection` CRUD with atomic update ops, typed queries, auth with a pluggable `SessionStore`, cloud functions, batch, file upload and live queries.
