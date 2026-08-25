import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = 'http://localhost:8080';

export const options = {
  stages: [
    { duration: '15s', target: 5 },
    { duration: '30s', target: 5 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

// Login ONCE per VU (setup runs once), reuse token for the whole test
export function setup() {
  const res = http.post(`${BASE}/auth/login`, JSON.stringify({
    identifier: '+917000000001',
    password: 'Passw0rd!123',
  }), { headers: { 'Content-Type': 'application/json' } });
  return { token: res.json('data.access_token') };
}

export default function (data) {
  const headers = { headers: { Authorization: `Bearer ${data.token}` } };
  const searchRes = http.get(`${BASE}/search/profiles?religion=Hindu&city=Mumbai`, headers);
  check(searchRes, { 'search ok': (r) => r.status === 200 });
  const matchRes = http.get(`${BASE}/matches/recommended`, headers);
  check(matchRes, { 'matches ok': (r) => r.status === 200 });
  sleep(1);
}
