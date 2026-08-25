import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = 'http://localhost:8080';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 50 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests should be under 500ms
    http_req_failed: ['rate<0.01'],   // less than 1% failures
  },
};

export default function () {
  // login (reuse a pre-seeded test user for the load test)
  const loginRes = http.post(`${BASE}/auth/login`, JSON.stringify({
    identifier: '+917000000001',
    password: 'Passw0rd!123',
  }), { headers: { 'Content-Type': 'application/json' } });

  check(loginRes, { 'login ok': (r) => r.status === 200 });
  const token = loginRes.json('data.access_token');

  const headers = { headers: { Authorization: `Bearer ${token}` } };

  // hit search
  const searchRes = http.get(`${BASE}/search/profiles?religion=Hindu&city=Mumbai`, headers);
  check(searchRes, { 'search ok': (r) => r.status === 200 });

  // hit recommended matches
  const matchRes = http.get(`${BASE}/matches/recommended`, headers);
  check(matchRes, { 'matches ok': (r) => r.status === 200 });

  sleep(1);
}