import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = 'http://localhost:58080';

export const options = {
  stages: [
    { duration: '30s', target: 100 },
    { duration: '1m', target: 200 },
    { duration: '1m', target: 200 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'],
    http_req_failed: ['rate<0.01'],
  },
};

export function setup() {
  const res = http.post(`${BASE}/auth/login`, JSON.stringify({
    identifier: '+15551234567',
    password: 'SuperSecret123',
  }), { headers: { 'Content-Type': 'application/json' } });
  return { token: res.json('data.access_token') };
}

export default function (data) {
  const headers = { headers: { Authorization: `Bearer ${data.token}` } };

  const searchRes = http.get(`${BASE}/search/profiles?religion=Hindu&city=Mumbai`, headers);
  check(searchRes, { 'search ok': (r) => r.status === 200 });

  const matchRes = http.get(`${BASE}/matches/recommended`, headers);
  check(matchRes, { 'matches ok': (r) => r.status === 200 });

  const dailyRes = http.get(`${BASE}/matches/daily`, headers);
  check(dailyRes, { 'daily ok': (r) => r.status === 200 });

  sleep(0.5);
}