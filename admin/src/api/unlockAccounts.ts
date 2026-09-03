import { apiClient } from './client';
import type {
  Envelope,
  ListMeta,
  ReconcileResponse,
  UnlockAccountRowResponse,
  UnlockRevenueSummaryResponse,
} from '../types/api';

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

export async function reconcileUnlockAccounts(): Promise<ReconcileResponse> {
  const { data } = await apiClient.post<Envelope<ReconcileResponse>>('/admin/unlock-accounts/reconcile');
  return data.data;
}

// CSV export is a direct browser download, not a fetch: the httpOnly
// session cookie (SameSite=None in prod) rides along on a plain
// cross-origin navigation the same way it does on any XHR, so opening
// this URL in a new tab downloads the file with no blob/JS handling
// needed.
export function unlockAccountsExportUrl(status?: string): string {
  const base = `${apiClient.defaults.baseURL}/admin/unlock-accounts/export`;
  return status ? `${base}?status=${encodeURIComponent(status)}` : base;
}
