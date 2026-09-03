import { apiClient } from './client';
import type { Envelope, ListMeta, UnlockAccountRowResponse, UnlockRevenueSummaryResponse } from '../types/api';

export interface ListUnlockAccountsParams {
  status?: string;
  page: number;
  limit: number;
}

export async function listUnlockAccounts(
  params: ListUnlockAccountsParams,
): Promise<{ rows: UnlockAccountRowResponse[]; meta: ListMeta }> {
  const { data } = await apiClient.get<Envelope<UnlockAccountRowResponse[]>>('/admin/unlock-accounts', { params });
  return { rows: data.data, meta: data.meta as ListMeta };
}

export async function getUnlockRevenueSummary(): Promise<UnlockRevenueSummaryResponse> {
  const { data } = await apiClient.get<Envelope<UnlockRevenueSummaryResponse>>('/admin/unlock-accounts/summary');
  return data.data;
}
