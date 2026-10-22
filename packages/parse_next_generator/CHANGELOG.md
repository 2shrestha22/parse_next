## 0.3.0

- Requires parse_next 0.3.0.
- Lists of `DateTime`, `GeoPoint`, `ParseFile` and `Map<String, Object?>` as fields, cloud function parameters and results.
- Map fields get `MapField` and `MapOps`, File fields `FileField`, Polygon fields `PolygonField`; pointer fields carry the target's fields type, relation fields its schema. Map values are encoded with `encodeValue`.

## 0.2.0

- Requires parse_next 0.2.0. Generated code is unchanged.

## 0.1.0

- First release: generates `XFields`, `XOps` and `$XSchema` for `@ParseClass` models, and a client for `@ParseFunctions` classes.
