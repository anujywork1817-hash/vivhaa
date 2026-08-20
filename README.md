# Vivaha

Matrimony app — Go backend + Flutter frontend, merged into one working
tree. Each half keeps its own build tooling and (for `backend/`) its own
git history/remote; this top-level folder just gives you one place to
open both from.

```
vivaha/
  backend/    Go API + workers (was matrimony_backend/) — see backend/README.md
  frontend/   Flutter app (was shadi.com/frontend/) — see frontend/README.md
  admin/      React admin panel (was shadi.com/admin/) — see admin/README.md
```

## Running everything together

1. **Backend** — from `backend/`:
   ```bash
   docker compose up -d
   curl http://localhost:58080/health
   ```
   First run also needs `.env` set up — see `backend/.env.example`.

2. **Frontend** — from `frontend/`:
   ```bash
   flutter pub get
   flutter run
   ```
   The app defaults to `_devMachineLanIp` in `lib/core/api/api_endpoints.dart`
   for real-device testing over WiFi, or override per-run with
   `--dart-define=API_BASE_URL=http://<host>:58080`.

3. **Admin panel** — from `admin/`:
   ```bash
   npm install
   npm run dev
   ```
   Points at the backend via `VITE_API_BASE_URL` in `admin/.env` (copy
   from `.env.example` if it's not there yet). Sign in with an account
   whose `role` is `admin` — see `admin/README.md` for how to promote one.

## Notes

- `backend/` is still the same git repo pushed to
  `https://github.com/anujywork1817-hash/matremony.git` — moving it here
  didn't touch its history, remote, or any deployed server pulling from
  that repo.
- `frontend/`'s git repo is mostly untracked (only a handful of files are
  actually committed) — worth cleaning up if you want real version
  history for it.
