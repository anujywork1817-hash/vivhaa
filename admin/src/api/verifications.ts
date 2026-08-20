import { apiClient } from './client';
import type { Envelope, ListMeta, ReviewRequest, VerificationResponse } from '../types/api';

export interface ListVerificationsParams {
  page: number;
  limit: number;
}

export async function listPendingVerifications(
  params: ListVerificationsParams,
): Promise<{ rows: VerificationResponse[]; meta: ListMeta }> {
  const { data } = await apiClient.get<Envelope<VerificationResponse[]>>('/admin/verifications', { params });
  return { rows: data.data, meta: data.meta as ListMeta };
}

export async function approveVerification(id: string, req: ReviewRequest): Promise<VerificationResponse> {
  const { data } = await apiClient.put<Envelope<VerificationResponse>>(`/admin/verifications/${id}/approve`, req);
  return data.data;
}

export async function rejectVerification(id: string, req: ReviewRequest): Promise<VerificationResponse> {
  const { data } = await apiClient.put<Envelope<VerificationResponse>>(`/admin/verifications/${id}/reject`, req);
  return data.data;
}
