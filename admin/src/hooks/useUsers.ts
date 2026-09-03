import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { activateUser, getUser, getUserFinance, listUsers, suspendUser, type ListUsersParams } from '../api/users';

export function useUsersList(params: ListUsersParams) {
  return useQuery({
    queryKey: ['users', params],
    queryFn: () => listUsers(params),
    placeholderData: (prev) => prev, // keep the old page visible while the next loads, no flash-to-blank
  });
}

export function useUser(id: string | undefined) {
  return useQuery({
    queryKey: ['user', id],
    queryFn: () => getUser(id as string),
    enabled: !!id,
  });
}

export function useUserFinance(id: string | undefined) {
  return useQuery({
    queryKey: ['user-finance', id],
    queryFn: () => getUserFinance(id as string),
    enabled: !!id,
  });
}

export function useSuspendUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: suspendUser,
    onSuccess: (_data, id) => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
      queryClient.invalidateQueries({ queryKey: ['user', id] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}

export function useActivateUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: activateUser,
    onSuccess: (_data, id) => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
      queryClient.invalidateQueries({ queryKey: ['user', id] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}
