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
  // Every VU used to log in fresh on every iteration — with a
  // ramping-vus executor and no sleep, that's up to 20 concurrent
  // logins for one identifier from one IP repeated every ~10s (each
  // iteration blocks for the WS connection's lifetime, not instant, but
  // still enough to exhaust the backend's per-IP/per-identifier login
  // rate limit within the first cycle and turn the rest of the run into
  // 401s that have nothing to do with the WS path actually under test.
  // Reuses one pre-minted token instead — sharing one identity across
  // many concurrent connections is exactly what Hub already supports
  // (multi-device), so it's still a real exercise of the hub's fan-out.
  let token = __ENV.TOKEN;
  if (!token) {
    const loginRes = http.post(`${BASE}/auth/login`, JSON.stringify({
      identifier: '+15556660001',
      password: 'SuperSecret123',
    }), { headers: { 'Content-Type': 'application/json' } });

    token = loginRes.json('data.access_token');
    if (!token) {
      console.log(`Login failed: ${loginRes.status} - ${loginRes.body}`);
      return;
    }
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