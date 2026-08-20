import { apiClient } from './client';
import type { DashboardResponse, Envelope } from '../types/api';

export async function getDashboard(): Promise<DashboardResponse> {
  const { data } = await apiClient.get<Envelope<DashboardResponse>>('/admin/dashboard');
  return data.data;
}
