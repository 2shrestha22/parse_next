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
  const echo = request => request.params.value;
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

// Do nothing on purpose: a trigger alone makes parse-server decode every
// object it sees into the JS SDK and encode it back (triggers.js), and a value
// the SDK cannot represent fails there, or kills the server. Item has none, so
// the queries on it still cover the path without them.
// Each also keeps the context it got, for `contextOf`.
const contexts = {};
for (const className of ['Post', '_User', 'Signal']) {
  for (const trigger of [
    'beforeSave', 'afterSave', 'beforeDelete', 'afterDelete', 'beforeFind',
    'afterFind',
  ]) {
    Parse.Cloud[trigger](className, request => {
      contexts[`${trigger} ${className}`] = request.context;
    });
  }
}
Parse.Cloud.define('contextOf', request => contexts[request.params.trigger]);

let savedFile;
Parse.Cloud.beforeSave(Parse.File, request => {
  savedFile = { metadata: request.file.metadata(), tags: request.file.tags() };
});
Parse.Cloud.define('savedFile', () => savedFile);

Parse.Cloud.define('headers', request => ({
  clientVersion: request.headers['x-parse-client-version'],
  installationId: request.installationId,
}));
Parse.Cloud.beforeLogin(() => {});
Parse.Cloud.afterLogin(() => {});
Parse.Cloud.afterLogout(() => {});
