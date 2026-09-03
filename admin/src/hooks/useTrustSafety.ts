import { useQuery } from '@tanstack/react-query';
import { getTrustSafety } from '../api/trustSafety';

export function useTrustSafety() {
  return useQuery({
    queryKey: ['trust-safety'],
    queryFn: getTrustSafety,
  });
}
