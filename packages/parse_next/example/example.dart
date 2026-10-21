import 'package:parse_next/parse_next.dart';

part 'example.parse.dart';

@ParseClass('_User')
final class User {
  const User({required this.username, this.email});

  final String username;
  final String? email;
}

@ParseClass('Post')
final class Post {
  const Post({
    required this.title,
    required this.likes,
    required this.tags,
    required this.author,
  });

  final String title;
  final int likes;
  final List<String> tags;
  final Pointer<User> author;
}

Future<void> main() async {
  final client = ParseClient(
    server: Uri.parse('http://localhost:1337/parse'),
    appId: 'myAppId',
  );
  final auth = client.auth(const $UserSchema());
  final posts = client.collection(const $PostSchema());

  try {
    final me = await auth.signUp(
      password: 'correct horse',
      user: const User(username: 'ada'),
    );

    final events = posts.where((f) => f.author.isId(me.id)).live().listen((
      event,
    ) {
      switch (event) {
        case Subscribed():
          print('subscribed');
        case Disconnected():
          print('disconnected');
        case Created(:final doc) || Updated(:final doc) || Entered(:final doc):
          print('${doc.data.title}: ${doc.data.likes} likes');
        case Left(:final doc) || Deleted(:final doc):
          print('gone: ${doc.id}');
      }
    });

    final post = await posts.create(
      Post(title: 'Hello', likes: 0, tags: const [], author: Pointer(me.id)),
    );
    await posts.update(
      post.id,
      (o) => [
        o.likes.increment(1),
        o.tags.addUnique(['news']),
      ],
    );

    final popular = await posts
        .where((f) => f.likes.gte(1) & f.tags.contains('news'))
        .orderBy((f) => f.likes.desc)
        .include((f) => f.author)
        .limit(10)
        .find();
    for (final p in popular) {
      print('${p.data.title} by ${p.data.author.loaded?.data.username}');
    }

    await events.cancel();
    await auth.logOut();
  } on ParseException catch (e) {
    switch (e) {
      case UsernameTaken():
        print('pick another username');
      case NetworkError():
        print('offline: ${e.message}');
      case _:
        print(e);
    }
  } finally {
    client.close();
  }
}
