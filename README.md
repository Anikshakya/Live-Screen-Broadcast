# mirror

## Tests

Run the full unit and widget test suite from the project root:

```sh
flutter test -r expanded
```

Run only unit tests:

```sh
flutter test test/unit
```

Run only widget tests:

```sh
flutter test test/widget
```

Device-backed integration tests are separate. For one device, run:

```sh
flutter test integration_test/app_test.dart -d <device-id>
```

For the two-device WebSocket test, run each command in a separate terminal:

```sh
# Host device
flutter test integration_test/two_device_test.dart -d D13E8BB9-DE87-43F5-AB6B-0DB528567FD8 --dart-define=ROLE=host --dart-define=MODE=websocket
```

```sh
# Client device
flutter test integration_test/two_device_test.dart -d CCF02B22-AAEA-41AC-98AF-E33E68E2AED1 --dart-define=ROLE=client --dart-define=MODE=websocket --dart-define=HOST_IP=192.168.1.4
```

The two-device test can also be run with `./run_two_devices.sh <host-device-id> <client-device-id> [websocket|firebase]`.

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


create a server folder
# Step 1: Navigate into your server folder
cd server

# Step 2: Initialize Node.js project (creates package.json)
npm init -y

# Step 3: Install the WebSocket package
npm install ws

add this to server.js
const { WebSocketServer } = require('ws');

const PORT = 8080;
const wss = new WebSocketServer({ port: PORT });
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  console.log(`[+] Device connected. Active devices: ${clients.size}`);
  // Broadcast events from App A to App B
  ws.on('message', (message) => {
    for (const client of clients) {
      if (client !== ws && client.readyState === ws.OPEN) {
        client.send(message.toString());
      }
    }
  });

  ws.on('close', () => {
    clients.delete(ws);
    console.log(`[-] Device disconnected. Active devices: ${clients.size}`);
  });
});

console.log(`🚀 Sync Server running on port ${PORT}`);