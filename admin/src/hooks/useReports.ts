import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { listPendingReports, resolveReport, type ListReportsParams } from '../api/reports';
import type { ResolveRequest } from '../types/api';

export function useReportsList(params: ListReportsParams) {
  return useQuery({
    queryKey: ['reports', params],
    queryFn: () => listPendingReports(params),
    placeholderData: (prev) => prev,
  });
}

export function useResolveReport() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, req }: { id: string; req: ResolveRequest }) => resolveReport(id, req),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reports'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['users'] }); // a suspend-on-resolve changes user status
    },
  });
}
