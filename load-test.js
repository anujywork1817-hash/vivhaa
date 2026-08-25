import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// ---- CONFIG: change this to your app's base URL ----
// IMPORTANT: must include the http:// or https:// scheme, e.g.
// 'http://192.168.1.222:58080'  (NOT just '192.168.1.222:58080')
const BASE_URL = 'http://192.168.1.222:58080';

// Custom metrics
const errorRate = new Rate('errors');
const apiDuration = new Trend('api_duration');

export const options = {
  // Ramping VU scenario: warms up, holds at peak, then ramps down
  stages: [
    { duration: '1m', target: 100 },   // warm-up
    { duration: '2m', target: 500 },   // ramp to 500 users
    { duration: '3m', target: 500 },   // hold at 500
    { duration: '2m', target: 1000 },  // ramp to 1000 users
    { duration: '5m', target: 1000 },  // hold at 1000 (peak load)
    { duration: '2m', target: 0 },     // ramp down
  ],

  thresholds: {
    http_req_duration: ['p(95)<800', 'p(99)<1500'], // 95% under 800ms
    http_req_failed: ['rate<0.01'],                  // <1% failed requests
    errors: ['rate<0.01'],
  },

  // Uncomment to prevent OOM on smaller test runners
  // discardResponseBodies: true,
};

export default function () {
  group('Homepage', function () {
    const res = http.get(`${BASE_URL}/`);
    const ok = check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 1s': (r) => r.timings.duration < 1000,
    });
    errorRate.add(!ok);
    apiDuration.add(res.timings.duration);
  });

  sleep(Math.random() * 2 + 1); // think time: 1-3s between actions

  group('Login flow (example)', function () {
    const loginRes = http.post(`${BASE_URL}/api/login`, JSON.stringify({
      username: `user_${__VU}`,
      password: 'testpassword',
    }), { headers: { 'Content-Type': 'application/json' } });

    const ok = check(loginRes, {
      'login status is 200': (r) => r.status === 200,
    });
    errorRate.add(!ok);
  });

  sleep(Math.random() * 2 + 1);

  group('API call (example)', function () {
    const res = http.get(`${BASE_URL}/api/data`);
    check(res, {
      'api status is 200': (r) => r.status === 200,
    });
  });

  sleep(1);
}