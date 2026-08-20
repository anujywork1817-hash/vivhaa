import { apiClient } from './client';
import type { Envelope, ListMeta, RevenueResponse, SubscriptionRowResponse } from '../types/api';

export interface ListSubscriptionsParams {
  status?: string;
  page: number;
  limit: number;
}

export async function listSubscriptions(
  params: ListSubscriptionsParams,
): Promise<{ rows: SubscriptionRowResponse[]; meta: ListMeta }> {
  const { data } = await apiClient.get<Envelope<SubscriptionRowResponse[]>>('/admin/subscriptions', { params });
  return { rows: data.data, meta: data.meta as ListMeta };
}

export async function getRevenue(): Promise<RevenueResponse> {
  const { data } = await apiClient.get<Envelope<RevenueResponse>>('/admin/revenue');
  return data.data;
}
