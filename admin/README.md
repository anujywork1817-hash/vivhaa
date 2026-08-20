# Vivaha Admin

Web-based admin panel for the Vivaha matrimony app. React + TypeScript +
Ant Design + TanStack Query + Recharts, talking only to the existing
`matrimony_backend` Go API — no direct database access. The same backend
the Flutter app uses; this is just another authenticated client of it.

## Run it

```bash
npm install
npm run dev
```

Copy `.env.example` to `.env` and point `VITE_API_BASE_URL` at your
`matrimony_backend` instance if it's not on `http://localhost:58080`.

Sign in with an account whose `role` is `admin` on the backend (see
`internal/admin` — promote a user via the database, there's no
self-service admin signup).

## Structure

```
src/
  api/         one file per backend resource — the only place HTTP calls happen
  hooks/       TanStack Query hooks wrapping api/ (caching, loading/error state)
  context/     AuthContext — session, login/logout, admin-role check
  components/  AppShell (sidebar/topbar), ProtectedRoute, LoadingState, ErrorState
  features/    one folder per screen (auth, dashboard, users, verifications, reports, subscriptions)
  theme/       neutral Ant Design theme override
  types/       TypeScript interfaces mirroring the Go DTOs 1:1
```

## Notes

- Auth: JWT access + refresh tokens in `localStorage`; a 401 triggers a
  single-flight refresh via `POST /auth/refresh-token` before retrying
  the original request.
- Every list screen is paginated against the backend's real
  `page`/`limit`/`meta.total`, not client-side slicing.
- Destructive actions (suspend, reject, resolve-with-suspend) always
  confirm first.
