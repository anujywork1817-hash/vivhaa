import { apiClient, tokenStorage } from './client';
import type { AuthResponse, Envelope } from '../types/api';

export async function login(identifier: string, password: string): Promise<AuthResponse> {
  const { data } = await apiClient.post<Envelope<AuthResponse>>('/auth/login', { identifier, password });
  return data.data;
}

export async function logout() {
  const refreshToken = tokenStorage.getRefreshToken();
  tokenStorage.clear();
  if (!refreshToken) return;
  try {
    // Best-effort: invalidates the refresh token server-side. A failure
    // here shouldn't block the local sign-out the user is waiting on.
    await apiClient.post('/auth/logout', { refresh_token: refreshToken });
  } catch {
    // ignore
  }
}
