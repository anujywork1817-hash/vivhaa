import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';
import { login as apiLogin, logout as apiLogout } from '../api/auth';
import { tokenStorage } from '../api/client';
import type { UserBrief } from '../types/api';

interface AuthContextValue {
  user: UserBrief | null;
  isAuthenticated: boolean;
  isAdmin: boolean;
  login: (identifier: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<UserBrief | null>(() => tokenStorage.getUser<UserBrief>());

  const login = useCallback(async (identifier: string, password: string) => {
    const res = await apiLogin(identifier, password);
    // Enforced here, not just server-side on protected routes: a
    // non-admin's credentials are otherwise perfectly valid and would
    // silently log them into a shell with every screen 403-ing one by
    // one. Reject up front with one clear message instead.
    if (res.user.role !== 'admin') {
      throw new Error('This account does not have admin access.');
    }
    // Session tokens are never stored here — the backend already set them
    // as httpOnly cookies as part of the login response. Only the
    // non-sensitive user object is cached, for UI display on refresh.
    tokenStorage.setUser(res.user);
    setUser(res.user);
  }, []);

  const logout = useCallback(async () => {
    await apiLogout();
    setUser(null);
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({ user, isAuthenticated: !!user, isAdmin: user?.role === 'admin', login, logout }),
    [user, login, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
