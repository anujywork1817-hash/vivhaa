import { Card, Col, Row, Select, Space, Statistic, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { useState } from 'react';
import { ErrorState } from '../../components/ErrorState';
import { useUnlockAccountsList, useUnlockRevenueSummary } from '../../hooks/useUnlockAccounts';
import type { UnlockAccountRowResponse } from '../../types/api';

const STATUS_COLORS: Record<string, string> = { paid: 'green', created: 'gold', failed: 'red' };

// Accounts: the ₹1 one-time unlock-gate's own accounts/revenue view —
// separate from the plan-based Subscriptions & Revenue page, since the
// unlock gate (internal/unlock, unlock_payments table) is a front toll,
// not a subscription plan.
export function AccountsPage() {
  const [status, setStatus] = useState<string | undefined>('paid');
  const [page, setPage] = useState(1);
  const [limit, setLimit] = useState(20);

  const { data, isPending, isError, error, refetch, isFetching } = useUnlockAccountsList({ status, page, limit });
  const { data: summary } = useUnlockRevenueSummary();

  const columns: ColumnsType<UnlockAccountRowResponse> = [
    {
      title: 'User',
      key: 'user',
      render: (_, row) => row.full_name ?? row.phone ?? row.email ?? '—',
    },
    {
      title: 'Amount',
      key: 'amount',
      render: (_, row) => `₹${row.amount_inr} ${row.currency}`,
    },
    {
      title: 'Status',
      dataIndex: 'status',
      render: (value: string) => <Tag color={STATUS_COLORS[value] ?? 'default'}>{value}</Tag>,
    },
    {
      title: 'Created',
      dataIndex: 'created_at',
      render: (value: string) => new Date(value).toLocaleString(),
    },
    {
      title: 'Paid at',
      dataIndex: 'paid_at',
      render: (value: string | null) => (value ? new Date(value).toLocaleString() : '—'),
    },
  ];

  return (
    <div>
      <Typography.Title level={3} style={{ marginTop: 0 }}>
        Accounts (₹1 Unlock)
      </Typography.Title>

      <Row gutter={16} style={{ marginBottom: 24 }}>
        <Col span={6}>
          <Card>
            <Statistic title="Paid accounts" value={summary?.total_paid_accounts ?? 0} valueStyle={{ color: '#389e0d' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic title="Checkout started" value={summary?.total_created_accounts ?? 0} valueStyle={{ color: '#d4b106' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic title="Failed" value={summary?.total_failed_accounts ?? 0} valueStyle={{ color: '#cf1322' }} />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic title="Total revenue" prefix="₹" value={summary?.total_revenue_inr ?? 0} />
          </Card>
        </Col>
      </Row>

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
                { value: 'paid', label: 'Paid' },
                { value: 'created', label: 'Created' },
                { value: 'failed', label: 'Failed' },
              ]}
            />
          </Space>

          <Table<UnlockAccountRowResponse>
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
