import { apiClient } from './client';
import type { Envelope, ListMeta, UserDetailResponse, UserResponse } from '../types/api';

export interface ListUsersParams {
  status?: string;
  role?: string;
  search?: string;
  page: number;
  limit: number;
}

export interface ListUsersResult {
  rows: UserResponse[];
  meta: ListMeta;
}

export async function listUsers(params: ListUsersParams): Promise<ListUsersResult> {
  const { data } = await apiClient.get<Envelope<UserResponse[]>>('/admin/users', { params });
  return { rows: data.data, meta: data.meta as ListMeta };
}

export async function getUser(id: string): Promise<UserDetailResponse> {
  const { data } = await apiClient.get<Envelope<UserDetailResponse>>(`/admin/users/${id}`);
  return data.data;
}

export async function suspendUser(id: string): Promise<UserResponse> {
  const { data } = await apiClient.put<Envelope<UserResponse>>(`/admin/users/${id}/suspend`);
  return data.data;
}

export async function activateUser(id: string): Promise<UserResponse> {
  const { data } = await apiClient.put<Envelope<UserResponse>>(`/admin/users/${id}/activate`);
  return data.data;
}
