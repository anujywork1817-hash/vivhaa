import { useQuery } from '@tanstack/react-query';
import { getRevenue, listSubscriptions, type ListSubscriptionsParams } from '../api/subscriptions';

export function useSubscriptionsList(params: ListSubscriptionsParams) {
  return useQuery({
    queryKey: ['subscriptions', params],
    queryFn: () => listSubscriptions(params),
    placeholderData: (prev) => prev,
  });
}

export function useRevenue() {
  return useQuery({
    queryKey: ['revenue'],
    queryFn: getRevenue,
  });
}
