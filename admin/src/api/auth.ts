import { apiClient, tokenStorage } from './client';
import type { AuthResponse, Envelope } from '../types/api';

export async function login(identifier: string, password: string): Promise<AuthResponse> {
  const { data } = await apiClient.post<Envelope<AuthResponse>>('/auth/login', { identifier, password });
  return data.data;
}

export async function logout() {
  tokenStorage.clear();
  try {
    // No body: the backend reads refresh_token from the httpOnly cookie
    // (see auth/handler.go's Logout) — this app never held a JS-readable
    // copy of it to send. Best-effort: invalidates the refresh token and
    // clears the cookies server-side; a failure here shouldn't block the
    // local sign-out the user is waiting on.
    await apiClient.post('/auth/logout', {});
  } catch {
    // ignore
  }
}
