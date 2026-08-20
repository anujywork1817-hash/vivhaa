import { useQuery } from '@tanstack/react-query';
import { listCallHistory, type ListCallHistoryParams } from '../api/calls';

export function useCallHistoryList(params: ListCallHistoryParams) {
  return useQuery({
    queryKey: ['call-history', params],
    queryFn: () => listCallHistory(params),
    placeholderData: (prev) => prev,
  });
}
