Parse.Cloud.define('fail', () => {
  throw new Error('fail was called');
});

Parse.Cloud.beforeSave('Note', request => {
  request.object.set('text', request.object.get('text').toUpperCase());
  request.object.unset('draft');
});

Parse.Cloud.define('sentMail', () => require('./email.js').sent);

for (const type of [
  'String', 'Int', 'Double', 'Num', 'Bool', 'Date', 'Enum', 'Strings',
  'Ints', 'Map', 'Pointer', 'Pointers', 'File', 'GeoPoint', 'Polygon',
  'Bytes',
]) {
  // A File param has no url, and returning a Parse.File without one crashes
  // the server (`Parse._encode` throws outside any handler).
  const echo = request =>
    type === 'File' ? request.params.value?.toJSON() : request.params.value;
  Parse.Cloud.define(`echo${type}`, echo);
  Parse.Cloud.define(`echoNullable${type}`, echo);
}

Parse.Cloud.define('paramKeys', request => Object.keys(request.params));

Parse.Cloud.define('ping', () => 'pong');
Parse.Cloud.define('returnsNull', () => null);
Parse.Cloud.define('returnsUndefined', () => undefined);

Parse.Cloud.define('failWithCode', request => {
  throw new Parse.Error(request.params.code, `failed with ${request.params.code}`);
});

Parse.Cloud.define('whoAmI', request => request.user);
Parse.Cloud.define('requireUser', request => request.user);

const usersNamed = usernames =>
  new Parse.Query(Parse.User)
    .containedIn('username', usernames)
    .ascending('username')
    .find({ useMasterKey: true });

Parse.Cloud.define('findUsers', request => usersNamed(request.params.usernames));
Parse.Cloud.define('findUsersOrNull', request =>
  request.params.usernames && usersNamed(request.params.usernames),
);

// The LiveQuery server's own count of connected sockets, as of its last
// subscribe, unsubscribe or disconnect; its connect events report the count
// from before the socket was added.
let liveClients = 0;
Parse.Cloud.onLiveQueryEvent(({ event, clients }) => {
  if (['subscribe', 'unsubscribe', 'ws_disconnect'].includes(event)) {
    liveClients = clients;
  }
});
Parse.Cloud.define('liveClients', () => liveClients);
