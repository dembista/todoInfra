const serverless = require('serverless-http');
const app = require('../../src/server');

const handler = serverless(app);

exports.handler = async (event, context) => {
  event.path = event.path.replace(/^\/\.netlify\/functions\/api/, '/api');
  if (!event.path || event.path === '/') event.path = '/api';
  return handler(event, context);
};