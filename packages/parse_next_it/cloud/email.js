// Records instead of sending, so tests can see which addresses got mail.
const sent = [];

module.exports = {
  sent,
  sendMail: async mail => {
    sent.push(mail.to);
  },
};
