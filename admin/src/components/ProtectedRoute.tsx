import type { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { isAuthenticated, isAdmin } = useAuth();
  if (!isAuthenticated) return <Navigate to="/login" replace />;
  // AuthContext.login already rejects a non-admin credential up front,
  // but that only covers the login moment — this re-checks on every
  // render (page refresh, cached session restore, a role that changed
  // server-side mid-session) rather than trusting whatever got the user
  // authenticated in the first place. Every real admin action is still
  // independently re-authorized server-side (RequireRole("admin")) no
  // matter what this route guard decides; this only prevents the admin
  // shell from rendering (with API calls that would just 403 anyway) for
  // someone this app itself shouldn't be treating as an admin.
  if (!isAdmin) return <Navigate to="/login" replace />;
  return <>{children}</>;
}
