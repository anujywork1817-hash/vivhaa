import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = 'http://localhost:8080';

export const options = {
  stages: [
    { duration: '30s', target: 200 },
    { duration: '30s', target: 500 },
    { duration: '30s', target: 800 },
    { duration: '30s', target: 1000 },
    { duration: '1m', target: 1000 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    http_req_failed: ['rate<0.05'],
  },
};

export function setup() {
  if (__ENV.TOKEN) return { token: __ENV.TOKEN };
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

  const dailyRes = http.get(`${BASE}/matches/daily`, headers);
  check(dailyRes, { 'daily ok': (r) => r.status === 200 });

  sleep(1);
}
