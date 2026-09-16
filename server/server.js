const { WebSocketServer } = require('ws');

const PORT = 8080;
const wss = new WebSocketServer({
  port: PORT,
  maxPayload: 100 * 1024 * 1024, // 100MB buffer limit
});

console.log(`🚀 WebSocket Sync Server running on port ${PORT}`);

wss.on('connection', (ws) => {
  console.log('[+] Client connected');

  ws.on('message', (data, isBinary) => {
    wss.clients.forEach((client) => {
      if (client !== ws && client.readyState === 1) { // 1 = OPEN
        client.send(data, { binary: isBinary });
      }
    });
  });

  ws.on('close', () => console.log('[-] Client disconnected'));
  ws.on('error', (err) => console.error('[!] Server Error:', err.message));
});