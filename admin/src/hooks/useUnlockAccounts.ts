import { useQuery } from '@tanstack/react-query';
import {
  getUnlockRevenueSummary,
  listUnlockAccounts,
  type ListUnlockAccountsParams,
} from '../api/unlockAccounts';

export function useUnlockAccountsList(params: ListUnlockAccountsParams) {
  return useQuery({
    queryKey: ['unlock-accounts', params],
    queryFn: () => listUnlockAccounts(params),
    placeholderData: (prev) => prev,
  });
}

export function useUnlockRevenueSummary() {
  return useQuery({
    queryKey: ['unlock-revenue-summary'],
    queryFn: getUnlockRevenueSummary,
  });
}
