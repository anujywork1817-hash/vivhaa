import { useQuery } from '@tanstack/react-query';
import { getDashboard } from '../api/dashboard';

export function useDashboard() {
  return useQuery({
    queryKey: ['dashboard'],
    queryFn: getDashboard,
    // Metrics/queue counts drift as admins work — a stale dashboard is
    // actively misleading (e.g. showing 3 pending reports after they've
    // all just been resolved), so refetch reasonably often rather than
    // relying only on manual refresh.
    refetchInterval: 30_000,
  });
}
