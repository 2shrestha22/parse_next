// Records instead of sending, so tests can see which devices a push reached.
const sent = [];

module.exports = {
  sent,
  getValidPushTypes: () => ['android'],
  send: async (body, installations) => {
    sent.push({ data: body.data, tokens: installations.map(i => i.deviceToken) });
    return installations.map(device => ({ device, transmitted: true }));
  },
};
