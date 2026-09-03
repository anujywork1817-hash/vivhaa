import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  getUnlockRevenueSummary,
  listUnlockAccounts,
  reconcileUnlockAccounts,
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

export function useReconcileUnlockAccounts() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: reconcileUnlockAccounts,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['unlock-accounts'] });
      queryClient.invalidateQueries({ queryKey: ['unlock-revenue-summary'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}
