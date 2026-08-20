import { apiClient } from './client';
import type { CallHistoryResponse, Envelope, ListMeta } from '../types/api';

export interface ListCallHistoryParams {
  status?: string;
  from?: string; // YYYY-MM-DD
  to?: string; // YYYY-MM-DD
  page: number;
  limit: number;
}

export async function listCallHistory(
  params: ListCallHistoryParams,
): Promise<{ rows: CallHistoryResponse[]; meta: ListMeta }> {
  const { data } = await apiClient.get<Envelope<CallHistoryResponse[]>>('/admin/call-history', { params });
  return { rows: data.data, meta: data.meta as ListMeta };
}
