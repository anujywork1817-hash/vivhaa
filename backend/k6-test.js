
import http from 'k6/http';
import { check, sleep } from 'k6';

// Base URL for the API under test
const BASE_URL = 'http://vivaha-api-prod-alb.eba-7txximqk.ap-south-1.elasticbeanstalk.com';


//http://vivaha-api-prod-alb.eba-7txximqk.ap-south-1.elasticbeanstalk.com/

// Test configuration
// Set K6_SCENARIO=diagnostic (env var) to run a gentle ramp first and find
// the breaking point before jumping straight to 500-1000 VUs.
// Usage: k6 run -e SCENARIO=diagnostic k6-test.js
const SCENARIO = __ENV.SCENARIO || 'full';

const stagesByScenario = {
  // Slow, small ramp to find where errors start creeping in
  diagnostic: [
    { duration: '30s', target: 20 },
    { duration: '1m', target: 20 },
    { duration: '30s', target: 50 },
    { duration: '1m', target: 50 },
    { duration: '30s', target: 100 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: 200 },
    { duration: '1m', target: 200 },
    { duration: '30s', target: 0 },
  ],
  // Full 500-1000 VU test
  full: [
    { duration: '1m', target: 200 },    // warm up
    { duration: '2m', target: 500 },    // ramp up to 500 VUs
    { duration: '3m', target: 500 },    // hold at 500 VUs
    { duration: '2m', target: 1000 },   // ramp up to 1000 VUs
    { duration: '5m', target: 1000 },   // hold at 1000 VUs
    { duration: '2m', target: 0 },      // ramp down
  ],
};

export const options = {
  stages: stagesByScenario[SCENARIO],
  thresholds: {
    http_req_duration: ['p(95)<1500'], // 95% of requests should be below 1.5s
    http_req_failed: ['rate<0.05'],    // error rate should be below 5%
  },
};

export default function () {
  // Simple GET request to the base URL / health check
  const res = http.get(`${BASE_URL}/`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 800ms': (r) => r.timings.duration < 800,
  });

  sleep(1);

  // Example: replace with your actual API endpoints
  // const loginRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
  //   username: 'testuser',
  //   password: 'testpass',
  // }), {
  //   headers: { 'Content-Type': 'application/json' },
  // });
  //
  // check(loginRes, {
  //   'login status is 200': (r) => r.status === 200,
  // });
  //
  // sleep(1);
}