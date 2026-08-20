import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  approveVerification,
  listPendingVerifications,
  listUserDocuments,
  rejectVerification,
  type ListVerificationsParams,
} from '../api/verifications';
import type { ReviewRequest } from '../types/api';

export function useVerificationsList(params: ListVerificationsParams) {
  return useQuery({
    queryKey: ['verifications', params],
    queryFn: () => listPendingVerifications(params),
    placeholderData: (prev) => prev,
  });
}

export function useUserDocuments(userId: string | undefined) {
  return useQuery({
    queryKey: ['userDocuments', userId],
    queryFn: () => listUserDocuments(userId as string),
    enabled: !!userId,
  });
}

export function useApproveVerification() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, req }: { id: string; req: ReviewRequest }) => approveVerification(id, req),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['verifications'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}

export function useRejectVerification() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, req }: { id: string; req: ReviewRequest }) => rejectVerification(id, req),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['verifications'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}
