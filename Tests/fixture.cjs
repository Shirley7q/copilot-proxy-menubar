const http = require('node:http');
const index = process.argv.indexOf('--port');
const port = Number(process.argv[index + 1]);
const server = http.createServer((request, response) => {
  response.writeHead(200, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify({ status: 'ready' }));
});
server.listen(port, '127.0.0.1', () => console.log('Fixture ready'));
process.on('SIGTERM', () => { server.closeAllConnections(); server.close(() => process.exit(0)); });
