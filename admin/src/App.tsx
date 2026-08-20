import { Navigate, Route, Routes } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { ProtectedRoute } from './components/ProtectedRoute';
import { LoginPage } from './features/auth/LoginPage';
import { CallHistoryPage } from './features/calls/CallHistoryPage';
import { DashboardPage } from './features/dashboard/DashboardPage';
import { ReportQueuePage } from './features/reports/ReportQueuePage';
import { SubscriptionsPage } from './features/subscriptions/SubscriptionsPage';
import { UserDetailPage } from './features/users/UserDetailPage';
import { UserListPage } from './features/users/UserListPage';
import { VerificationQueuePage } from './features/verifications/VerificationQueuePage';

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route
        element={
          <ProtectedRoute>
            <AppShell />
          </ProtectedRoute>
        }
      >
        <Route path="/" element={<DashboardPage />} />
        <Route path="/users" element={<UserListPage />} />
        <Route path="/users/:id" element={<UserDetailPage />} />
        <Route path="/verifications" element={<VerificationQueuePage />} />
        <Route path="/reports" element={<ReportQueuePage />} />
        <Route path="/subscriptions" element={<SubscriptionsPage />} />
        <Route path="/call-history" element={<CallHistoryPage />} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
