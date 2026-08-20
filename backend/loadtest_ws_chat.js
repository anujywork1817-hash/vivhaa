import ws from 'k6/ws';
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = 'http://localhost:58080';
const WS_BASE = 'ws://localhost:58080';
const PARTNER_USER_ID = 'd1ff7fac-322f-4fd8-85cc-8d12c85d491b';

export const options = {
  scenarios: {
    chat_ws: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '15s', target: 20 },
        { duration: '30s', target: 20 },
        { duration: '15s', target: 0 },
      ],
    },
  },
};

export default function () {
  // Log in fresh for this VU
  const loginRes = http.post(`${BASE}/auth/login`, JSON.stringify({
    identifier: '+15556660001',
    password: 'SuperSecret123',
  }), { headers: { 'Content-Type': 'application/json' } });

  const token = loginRes.json('data.access_token');
  if (!token) {
    console.log(`Login failed: ${loginRes.status} - ${loginRes.body}`);
    return;
  }

  const url = `${WS_BASE}/ws/chat?token=${token}`;
  let messagesSent = 0;
  let messagesReceived = 0;

  const res = ws.connect(url, {}, function (socket) {
    socket.on('open', () => {
      // Send a few messages once connected
      socket.setInterval(() => {
        socket.send(JSON.stringify({
          receiver_user_id: PARTNER_USER_ID,
          body: `WS load test message ${Date.now()}`,
        }));
        messagesSent++;
      }, 1000); // one message per second per connection
    });

    socket.on('message', (data) => {
      messagesReceived++;
      const parsed = JSON.parse(data);
      check(parsed, {
        'message type valid': (m) => m.type === 'message' || m.type === 'error',
      });
    });

    socket.on('error', (e) => {
      console.log(`WS error: ${e.error()}`);
    });

    // keep each connection open for 10 seconds, then close
    socket.setTimeout(() => {
      socket.close();
    }, 10000);
  });

  check(res, { 'ws connected': (r) => r && r.status === 101 });
}