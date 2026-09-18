// k6 load test for the Vivaha matrimony backend (AWS Elastic Beanstalk,
// fronted by CloudFront — see BASE_URL below).
//
// Ramps from 0 up to somewhere between 500 and 1000 concurrent virtual
// users (VUs), holds there, then ramps back down. Each VU signs up a
// brand-new throwaway account (the backend has no read-only "browse as
// guest" endpoint), then exercises a handful of common authenticated
// reads — dashboard, recommended matches, profile detail — the same mix
// a real new user's first session looks like.
//
// !! WARNING — this creates one real row in the `users` table (plus a
// `profiles` row) per iteration. At 1000 VUs over a multi-minute test
// that is thousands of throwaway accounts hitting production. Either:
//   - point BASE_URL at a staging/non-prod environment, or
//   - be ready to clean up test accounts afterward (they're easy to spot:
//     email like loadtest-<vu>-<iter>-...@example.com), or
//   - coordinate the run with whoever owns the RDS instance so it isn't
//     mistaken for an attack / doesn't blow through a cost budget.
//
// Install k6: https://k6.io/docs/get-started/installation/
// Run:
//   k6 run test.js
//   k6 run -e BASE_URL=https://your-env.example.com -e MAX_VUS=750 test.js
//   k6 run -e TARGET_RPS=... test.js   # see the alternate "read-only" scenario below
//
// Results: k6 prints a summary to stdout when the run finishes — no
// separate dashboard needed for a one-off run. For a live dashboard, add
// `--out cloud` (k6 Cloud, paid) or run `k6 run --out json=results.json
// test.js` and load that into Grafana separately.

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter } from 'k6/metrics';

// ---- Config -----------------------------------------------------------

// The API's own CloudFront front (not the raw Elastic Beanstalk URL —
// same reasoning as the app/admin panel: avoids mixed-content/DNS churn
// if the underlying EB environment is ever swapped). Override with
// -e BASE_URL=... to point this at a different environment entirely.
const BASE_URL = __ENV.BASE_URL || 'https://d1xh1vz5xjcutq.cloudfront.net';

// Peak concurrent VUs for the plateau stage — pass -e MAX_VUS=1000 (or
// any value in the 500-1000 range the task asked for) to tune it.
const MAX_VUS = parseInt(__ENV.MAX_VUS || '750', 10);

// How long to ramp up, hold, and ramp down. Keep the ramp gradual —
// slamming straight to 1000 VUs at t=0 tests your load balancer's cold
// start more than your app.
const RAMP_UP = __ENV.RAMP_UP || '2m';
const HOLD = __ENV.HOLD || '5m';
const RAMP_DOWN = __ENV.RAMP_DOWN || '2m';

// A shared secret prefix so every account this script ever creates is
// trivially greppable in the users table for cleanup:
//   DELETE FROM users WHERE email LIKE 'loadtest-%@example.com';
const EMAIL_PREFIX = 'loadtest';

const signupFailures = new Counter('signup_failures');

export const options = {
  stages: [
    { duration: RAMP_UP, target: MAX_VUS },
    { duration: HOLD, target: MAX_VUS },
    { duration: RAMP_DOWN, target: 0 },
  ],
  thresholds: {
    // Fail the whole run loudly if things are clearly on fire, rather
    // than a wall of red text you have to eyeball for the real signal.
    http_req_failed: ['rate<0.05'], // <5% of requests errored
    http_req_duration: ['p(95)<3000'], // 95% of requests under 3s
  },
  // Each VU gets its own cookie jar / connection — matches how distinct
  // real users hit the API (no shared session state between VUs).
  discardResponseBodies: false,
};

function randomSuffix() {
  return `${__VU}-${__ITER}-${Math.floor(Math.random() * 1e9)}`;
}

function jsonHeaders(token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  return { headers };
}

// ---- Scenario: signup -> browse (the default, realistic-but-writes) ---

export default function () {
  const suffix = randomSuffix();
  const email = `${EMAIL_PREFIX}-${suffix}@example.com`;
  const password = 'LoadTest123!';

  let accessToken;

  group('signup', () => {
    const res = http.post(
      `${BASE_URL}/auth/signup`,
      JSON.stringify({ email, password }),
      jsonHeaders(),
    );
    const ok = check(res, {
      'signup succeeded': (r) => r.status === 200 || r.status === 201,
    });
    if (!ok) {
      signupFailures.add(1);
      return;
    }
    const body = res.json();
    accessToken = body && body.data && body.data.access_token;
  });

  if (!accessToken) {
    // No point continuing this iteration without a session — count the
    // failure above and move on to the next one.
    sleep(1);
    return;
  }

  group('create minimal profile', () => {
    const res = http.post(
      `${BASE_URL}/profiles`,
      JSON.stringify({
        full_name: `Load Test ${suffix}`,
        gender: __VU % 2 === 0 ? 'male' : 'female',
        date_of_birth: '1996-01-01',
      }),
      jsonHeaders(accessToken),
    );
    check(res, { 'profile created': (r) => r.status === 200 || r.status === 201 });
  });

  // A short think-time between requests — real users don't fire requests
  // back-to-back with zero delay, and a completely delay-free loop mostly
  // just measures how fast k6's own network stack can go.
  sleep(Math.random() * 2 + 1);

  group('browse', () => {
    const me = http.get(`${BASE_URL}/profiles/me`, jsonHeaders(accessToken));
    check(me, { 'no 5xx on /profiles/me': (r) => r.status < 500 });

    const matches = http.get(`${BASE_URL}/matches/recommended`, jsonHeaders(accessToken));
    // Expected to be 402 (unlock_required) for a brand-new account — see
    // internal/middleware.RequireUnlocked — so this only checks for a
    // genuine server error, not a particular success status.
    check(matches, { 'no 5xx on /matches/recommended': (r) => r.status < 500 });

    const reference = http.get(`${BASE_URL}/reference/religions`, jsonHeaders(accessToken));
    check(reference, { 'no 5xx on /reference/religions': (r) => r.status < 500 });
  });

  sleep(Math.random() * 3 + 1);
}

// ---- Alternate scenario: pure read-only, no account creation ----------
//
// Use this instead of the default export when you want load on the API
// without writing thousands of rows — good for a first smoke run, or
// when testing directly against prod without a cleanup plan. Run it with:
//   k6 run -e SCENARIO=readonly test.js
// (k6 doesn't support switching the exported default function via env
// var at parse time on its own, so this is here as a template — copy its
// body into `export default` above, or run it as a second, separate
// script, if you want the read-only version instead.)
export function readOnlyScenario() {
  const health = http.get(`${BASE_URL}/health`);
  check(health, { 'health check OK': (r) => r.status === 200 });
  sleep(1);
}
