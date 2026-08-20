import { Select, Space, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { useState } from 'react';
import { ErrorState } from '../../components/ErrorState';
import { useSubscriptionsList } from '../../hooks/useSubscriptions';
import type { SubscriptionRowResponse } from '../../types/api';
import { RevenueChart } from './RevenueChart';

const STATUS_COLORS: Record<string, string> = { active: 'green', pending: 'gold', expired: 'default', cancelled: 'red' };

export function SubscriptionsPage() {
  const [status, setStatus] = useState<string | undefined>('active');
  const [page, setPage] = useState(1);
  const [limit, setLimit] = useState(20);

  const { data, isPending, isError, error, refetch, isFetching } = useSubscriptionsList({ status, page, limit });

  const columns: ColumnsType<SubscriptionRowResponse> = [
    {
      title: 'User',
      key: 'user',
      render: (_, row) => row.full_name ?? row.phone ?? row.email ?? '—',
    },
    { title: 'Plan', dataIndex: 'plan_name' },
    {
      title: 'Status',
      dataIndex: 'status',
      render: (value: string) => <Tag color={STATUS_COLORS[value] ?? 'default'}>{value}</Tag>,
    },
    {
      title: 'Started',
      dataIndex: 'starts_at',
      render: (value: string | null) => (value ? new Date(value).toLocaleDateString() : '—'),
    },
    {
      title: 'Expires',
      dataIndex: 'ends_at',
      render: (value: string | null) => (value ? new Date(value).toLocaleDateString() : '—'),
    },
  ];

  return (
    <div>
      <Typography.Title level={3} style={{ marginTop: 0 }}>
        Subscriptions & Revenue
      </Typography.Title>

      <RevenueChart />

      <Typography.Title level={4} style={{ marginTop: 32 }}>
        Subscriptions
      </Typography.Title>

      {isError ? (
        <ErrorState error={error} onRetry={refetch} />
      ) : (
        <>
          <Space style={{ marginBottom: 16 }}>
            <Select
              placeholder="Status"
              allowClear
              style={{ width: 180 }}
              value={status}
              onChange={(v) => {
                setStatus(v);
                setPage(1);
              }}
              options={[
                { value: 'active', label: 'Active' },
                { value: 'pending', label: 'Pending' },
                { value: 'expired', label: 'Expired' },
                { value: 'cancelled', label: 'Cancelled' },
              ]}
            />
          </Space>

          <Table<SubscriptionRowResponse>
            rowKey="id"
            columns={columns}
            dataSource={data?.rows ?? []}
            loading={isPending || isFetching}
            pagination={{
              current: page,
              pageSize: limit,
              total: data?.meta.total ?? 0,
              showSizeChanger: true,
              onChange: (p, ps) => {
                setPage(p);
                setLimit(ps);
              },
            }}
          />
        </>
      )}
    </div>
  );
}
