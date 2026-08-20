import { apiClient } from './client';
import type { Envelope, ListMeta, ReportResponse, ResolveRequest } from '../types/api';

export interface ListReportsParams {
  page: number;
  limit: number;
}

export async function listPendingReports(
  params: ListReportsParams,
): Promise<{ rows: ReportResponse[]; meta: ListMeta }> {
  const { data } = await apiClient.get<Envelope<ReportResponse[]>>('/admin/reports', { params });
  return { rows: data.data, meta: data.meta as ListMeta };
}

export async function resolveReport(id: string, req: ResolveRequest): Promise<ReportResponse> {
  const { data } = await apiClient.put<Envelope<ReportResponse>>(`/admin/reports/${id}/resolve`, req);
  return data.data;
}
