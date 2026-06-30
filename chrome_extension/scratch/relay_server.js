// relay_server.js for AKRAMYG Zero-Knowledge P2P Cloud Sync
// Run: node relay_server.js [port]

const http = require('http');
const url = require('url');

const PORT = process.argv[2] || 8081;
const mailboxes = new Map(); // channelId -> base64 payload

const server = http.createServer((req, res) => {
  // CORS Headers
  const origin = req.headers.origin || '*';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Accept');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = url.parse(req.url, true);
  const pathParts = parsedUrl.pathname.split('/').filter(Boolean);

  // Endpoint: /relay/:channel
  if (pathParts[0] === 'relay' && pathParts[1]) {
    const channel = pathParts[1];

    if (req.method === 'GET') {
      const payload = mailboxes.get(channel) || '';
      // Delete payload upon consumption (transient mailbox)
      mailboxes.delete(channel);

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ payload }));
      console.log(`[Relay] GET on channel "${channel}" - Data consumed and cleared.`);
      return;
    }

    if (req.method === 'POST') {
      let body = '';
      req.on('data', chunk => {
        body += chunk;
      });
      req.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.payload) {
            mailboxes.set(channel, parsed.payload);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: true }));
            console.log(`[Relay] POST on channel "${channel}" - Encrypted envelope stored.`);
          } else {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Missing payload parameter.' }));
          }
        } catch (e) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Invalid JSON request body.' }));
        }
      });
      return;
    }
  }

  // Not Found
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not Found' }));
});

server.listen(PORT, () => {
  console.log(`AKRAMYG Zero-Knowledge Relay Server running at http://localhost:${PORT}`);
  console.log(`Point your extension and Android app's Relay URL to this endpoint.`);
});
