import axios, { type AxiosError, type InternalAxiosRequestConfig } from 'axios';
import type { AuthResponse, Envelope } from '../types/api';

// USER_KEY only ever caches the non-sensitive UserBrief (id/phone/email/
// role) for restoring "who's logged in" UI on a page refresh without a
// dedicated /auth/me endpoint. The actual session lives in httpOnly
// access_token/refresh_token cookies the backend sets on login/refresh
// (auth/handler.go's setAuthCookies) — NOT in localStorage. A raw bearer
// token sitting in localStorage is readable (and stealable) by any XSS
// bug anywhere in this app; an httpOnly cookie is invisible to JS
// entirely, so there is nothing here for such a bug to steal.
const USER_KEY = 'admin_user';

export const tokenStorage = {
  // Best-effort cache only — never the source of truth for "is this user
  // actually an admin". Every real admin action is re-authorized
  // server-side (RequireRole("admin")) regardless of what this returns;
  // this is UI convenience, not a security boundary.
  getUser: <T,>(): T | null => {
    const raw = localStorage.getItem(USER_KEY);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as T;
    } catch {
      // Malformed cached value (manual edit, partial write) — treat as
      // logged out rather than throwing uncaught on every app load.
      localStorage.removeItem(USER_KEY);
      return null;
    }
  },
  setUser: (user: unknown) => localStorage.setItem(USER_KEY, JSON.stringify(user)),
  clear: () => {
    localStorage.removeItem(USER_KEY);
  },
};

export const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL,
  headers: { 'Content-Type': 'application/json' },
  // Required so the browser actually sends the httpOnly session cookies
  // on every request (and accepts new ones from Set-Cookie responses) —
  // without this, a cross-origin request (the admin panel is typically a
  // separate origin from the API) omits cookies entirely.
  withCredentials: true,
});

// Single-flight refresh: concurrent 401s while a refresh is already in
// flight all wait on the same promise instead of each firing their own
// refresh request (which would race and likely invalidate each other's
// new refresh token — the backend rotates it on every use).
let refreshPromise: Promise<void> | null = null;

async function refreshAccessToken(): Promise<void> {
  // No body: the backend falls back to the refresh_token cookie when the
  // JSON body doesn't carry one (see auth/handler.go's Refresh) — this
  // app no longer keeps a JS-readable copy of that token to send.
  const { data } = await axios.post<Envelope<AuthResponse>>(
    `${import.meta.env.VITE_API_BASE_URL}/auth/refresh-token`,
    {},
    { withCredentials: true },
  );
  // The refresh response carries the same user object login does, but it
  // was being dropped here — if a role/status changed server-side, the
  // cached user in localStorage stayed stale until the next full login.
  tokenStorage.setUser(data.data.user);
}

apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const original = error.config as (InternalAxiosRequestConfig & { _retried?: boolean }) | undefined;
    if (error.response?.status !== 401 || !original || original._retried) {
      throw error;
    }
    original._retried = true;

    try {
      refreshPromise ??= refreshAccessToken().finally(() => {
        refreshPromise = null;
      });
      await refreshPromise;
      // The new access_token cookie is set by the browser itself from the
      // refresh response's Set-Cookie header — no header to attach here,
      // just replay the original request so it picks it up.
      return apiClient(original);
    } catch {
      tokenStorage.clear();
      window.location.href = '/login';
      throw error;
    }
  },
);
