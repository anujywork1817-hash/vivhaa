import { apiClient } from './client';
import type { Envelope, TrustSafetyResponse } from '../types/api';

export async function getTrustSafety(): Promise<TrustSafetyResponse> {
  const { data } = await apiClient.get<Envelope<TrustSafetyResponse>>('/admin/trust-safety');
  return data.data;
}
