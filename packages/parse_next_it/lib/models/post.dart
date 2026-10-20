import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';

import 'user.dart';

part 'post.parse.dart';

enum PostStatus { draft, published, archived }

@ParseClass('Post')
final class Post {
  const Post({
    required this.title,
    this.subtitle,
    required this.likes,
    this.views,
    required this.rating,
    this.ratio,
    required this.score,
    this.weight,
    required this.published,
    this.pinned,
    @ParseKey('published_at') required this.publishedAt,
    this.editedAt,
    required this.status,
    this.previousStatus,
    required this.tags,
    this.ranks,
    required this.meta,
    this.extra,
    required this.author,
    this.editor,
    required this.coauthors,
    this.reviewers,
    this.followers = const Relation(),
    required this.cover,
    this.attachment,
    required this.location,
    required this.area,
    this.zone,
    @ParseKey('thumb') required this.thumbnail,
    this.data,
  });

  final String title;
  final String? subtitle;
  final int likes;
  final int? views;
  final double rating;
  final double? ratio;
  final num score;
  final num? weight;
  final bool published;
  final bool? pinned;
  final DateTime publishedAt;
  final DateTime? editedAt;
  final PostStatus status;
  final PostStatus? previousStatus;
  final List<String> tags;
  final List<int>? ranks;
  final Map<String, Object?> meta;
  final Map<String, Object?>? extra;
  final Pointer<User> author;
  final Pointer<User>? editor;
  final List<Pointer<User>> coauthors;
  final List<Pointer<User>>? reviewers;
  final Relation<User> followers;
  final ParseFile cover;
  final ParseFile? attachment;

  /// The only GeoPoint field, so the nullable variant lives on Note: the
  /// server allows one per class (`validateObject` in SchemaController.js).
  final GeoPoint location;
  final Polygon area;
  final Polygon? zone;
  final Uint8List thumbnail;
  final Uint8List? data;
}
