// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'post.dart';

final class PostFields extends Fields<Post> {
  const PostFields();

  StringField<Post> get title => const StringField('title');
  StringField<Post> get subtitle => const StringField('subtitle');
  ComparableField<Post, int> get likes => const ComparableField('likes');
  ComparableField<Post, int> get views => const ComparableField('views');
  ComparableField<Post, double> get rating => const ComparableField('rating');
  ComparableField<Post, double> get ratio => const ComparableField('ratio');
  ComparableField<Post, num> get score => const ComparableField('score');
  ComparableField<Post, num> get weight => const ComparableField('weight');
  Field<Post, bool> get published => const Field('published');
  Field<Post, bool> get pinned => const Field('pinned');
  ComparableField<Post, DateTime> get publishedAt =>
      const ComparableField('published_at', encodeDate);
  ComparableField<Post, DateTime> get editedAt =>
      const ComparableField('editedAt', encodeDate);
  Field<Post, PostStatus> get status => Field('status', (v) => v.name);
  Field<Post, PostStatus> get previousStatus =>
      Field('previousStatus', (v) => v.name);
  ListField<Post, String> get tags => const ListField('tags');
  ListField<Post, int> get ranks => const ListField('ranks');
  ExistsField<Post> get meta => const ExistsField('meta');
  ExistsField<Post> get extra => const ExistsField('extra');
  PointerField<Post, User> get author =>
      const PointerField('author', $UserSchema());
  PointerField<Post, User> get editor =>
      const PointerField('editor', $UserSchema());
  PointerListField<Post, User> get coauthors =>
      PointerListField('coauthors', const $UserSchema());
  PointerListField<Post, User> get reviewers =>
      PointerListField('reviewers', const $UserSchema());
  RelationField<Post, User> get followers =>
      const RelationField('followers', $PostSchema());
  ExistsField<Post> get cover => const ExistsField('cover');
  ExistsField<Post> get attachment => const ExistsField('attachment');
  GeoField<Post> get location => const GeoField('location');
  ExistsField<Post> get area => const ExistsField('area');
  ExistsField<Post> get zone => const ExistsField('zone');
  ExistsField<Post> get thumbnail => const ExistsField('thumb');
  ExistsField<Post> get data => const ExistsField('data');
}

final class PostOps {
  const PostOps();

  SetOps<String> get title => const SetOps('title');
  NullableSetOps<String> get subtitle => const NullableSetOps('subtitle');
  NumOps<int> get likes => const NumOps('likes');
  NullableNumOps<int> get views => const NullableNumOps('views');
  NumOps<double> get rating => const NumOps('rating');
  NullableNumOps<double> get ratio => const NullableNumOps('ratio');
  NumOps<num> get score => const NumOps('score');
  NullableNumOps<num> get weight => const NullableNumOps('weight');
  SetOps<bool> get published => const SetOps('published');
  NullableSetOps<bool> get pinned => const NullableSetOps('pinned');
  SetOps<DateTime> get publishedAt => const SetOps('published_at', encodeDate);
  NullableSetOps<DateTime> get editedAt =>
      const NullableSetOps('editedAt', encodeDate);
  SetOps<PostStatus> get status => SetOps('status', (v) => v.name);
  NullableSetOps<PostStatus> get previousStatus =>
      NullableSetOps('previousStatus', (v) => v.name);
  ListOps<String> get tags => const ListOps('tags');
  NullableListOps<int> get ranks => const NullableListOps('ranks');
  SetOps<Map<String, Object?>> get meta => const SetOps('meta');
  NullableSetOps<Map<String, Object?>> get extra =>
      const NullableSetOps('extra');
  SetOps<Pointer<User>> get author =>
      SetOps('author', (v) => v.encode(const $UserSchema()));
  NullableSetOps<Pointer<User>> get editor =>
      NullableSetOps('editor', (v) => v.encode(const $UserSchema()));
  ListOps<Pointer<User>> get coauthors =>
      ListOps('coauthors', (v) => v.encode(const $UserSchema()));
  NullableListOps<Pointer<User>> get reviewers =>
      NullableListOps('reviewers', (v) => v.encode(const $UserSchema()));
  RelationOps<User> get followers =>
      const RelationOps('followers', $UserSchema());
  SetOps<ParseFile> get cover => SetOps('cover', (v) => v.toJson());
  NullableSetOps<ParseFile> get attachment =>
      NullableSetOps('attachment', (v) => v.toJson());
  SetOps<GeoPoint> get location => SetOps('location', (v) => v.toJson());
  SetOps<Polygon> get area => SetOps('area', (v) => v.toJson());
  NullableSetOps<Polygon> get zone => NullableSetOps('zone', (v) => v.toJson());
  SetOps<Uint8List> get thumbnail => const SetOps('thumb', encodeBytes);
  NullableSetOps<Uint8List> get data =>
      const NullableSetOps('data', encodeBytes);
}

final class $PostSchema implements ParseSchema<Post, PostFields, PostOps> {
  const $PostSchema();

  @override
  String get className => 'Post';

  @override
  Post decode(Json json) => Post(
    title: json.require<String>('title'),
    subtitle: json.opt<String>('subtitle'),
    likes: json.require<int>('likes'),
    views: json.opt<int>('views'),
    rating: json.require<double>('rating'),
    ratio: json.opt<double>('ratio'),
    score: json.require<num>('score'),
    weight: json.opt<num>('weight'),
    published: json.require<bool>('published'),
    pinned: json.opt<bool>('pinned'),
    publishedAt: json.require<DateTime>('published_at'),
    editedAt: json.opt<DateTime>('editedAt'),
    status: json.requireEnum('status', PostStatus.values),
    previousStatus: json.optEnum('previousStatus', PostStatus.values),
    tags: json.requireList<String>('tags'),
    ranks: json.optList<int>('ranks'),
    meta: json.require<Map<String, Object?>>('meta'),
    extra: json.opt<Map<String, Object?>>('extra'),
    author: json.requirePointer('author', const $UserSchema()),
    editor: json.optPointer('editor', const $UserSchema()),
    coauthors: json.requirePointerList('coauthors', const $UserSchema()),
    reviewers: json.optPointerList('reviewers', const $UserSchema()),
    followers: json.relation('followers', const $UserSchema()),
    cover: json.require<ParseFile>('cover'),
    attachment: json.opt<ParseFile>('attachment'),
    location: json.require<GeoPoint>('location'),
    area: json.require<Polygon>('area'),
    zone: json.opt<Polygon>('zone'),
    thumbnail: json.require<Uint8List>('thumb'),
    data: json.opt<Uint8List>('data'),
  );

  @override
  Json encode(Post value) => Json({
    'title': value.title,
    'subtitle': value.subtitle,
    'likes': value.likes,
    'views': value.views,
    'rating': value.rating,
    'ratio': value.ratio,
    'score': value.score,
    'weight': value.weight,
    'published': value.published,
    'pinned': value.pinned,
    'published_at': encodeDate(value.publishedAt),
    'editedAt': value.editedAt == null ? null : encodeDate(value.editedAt!),
    'status': value.status.name,
    'previousStatus': value.previousStatus?.name,
    'tags': value.tags,
    'ranks': value.ranks,
    'meta': value.meta,
    'extra': value.extra,
    'author': value.author.encode(const $UserSchema()),
    'editor': value.editor?.encode(const $UserSchema()),
    'coauthors': [
      for (final p in value.coauthors) p.encode(const $UserSchema()),
    ],
    'reviewers': value.reviewers == null
        ? null
        : [for (final p in value.reviewers!) p.encode(const $UserSchema())],
    'cover': value.cover.toJson(),
    'attachment': value.attachment?.toJson(),
    'location': value.location.toJson(),
    'area': value.area.toJson(),
    'zone': value.zone?.toJson(),
    'thumb': encodeBytes(value.thumbnail),
    'data': value.data == null ? null : encodeBytes(value.data!),
  });

  @override
  PostFields get fields => const PostFields();

  @override
  PostOps get ops => const PostOps();
}
