import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = 'http://localhost:58080';

// ⚠️ Replace these with real values from your database
const PARTNER_USER_ID = 'd1ff7fac-322f-4fd8-85cc-8d12c85d491b';

export const options = {
  stages: [
    { duration: '20s', target: 20 },
    { duration: '40s', target: 20 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export function setup() {
  const res = http.post(`${BASE}/auth/login`, JSON.stringify({
    identifier: '+15556660001',
    password: 'SuperSecret123',
  }), { headers: { 'Content-Type': 'application/json' } });
  return { token: res.json('data.access_token') };
}

export default function (data) {
  const headers = { headers: { Authorization: `Bearer ${data.token}`, 'Content-Type': 'application/json' } };

  // Profile update — hits Postgres write + publishes profile.updated to Kafka
  const updateRes = http.put(`${BASE}/profiles/me`, JSON.stringify({
    about_me: `Load test update ${Date.now()}`,
  }), headers);
  check(updateRes, { 'profile update ok': (r) => r.status === 200 });

  // Chat send — hits Postgres write + gating check + notification dispatch
  const chatRes = http.post(`${BASE}/chat/messages/${PARTNER_USER_ID}`, JSON.stringify({
    body: `Load test message ${Date.now()}`,
  }), headers);
  
  if (chatRes.status !== 201 && chatRes.status !== 200) {
    console.log(`Chat failed: ${chatRes.status} - ${chatRes.body}`);
  }
  check(chatRes, { 'chat send ok': (r) => r.status === 201 || r.status === 200 });;
}