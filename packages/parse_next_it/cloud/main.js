Parse.Cloud.define('fail', () => {
  throw new Error('fail was called');
});

Parse.Cloud.beforeSave('Note', request => {
  request.object.set('text', request.object.get('text').toUpperCase());
  request.object.unset('draft');
});
