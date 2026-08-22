import { Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { useState } from 'react';
import { ErrorState } from '../../components/ErrorState';
import { useReportsList } from '../../hooks/useReports';
import type { ReportResponse } from '../../types/api';
import { ReportDetailDrawer } from './ReportDetailDrawer';

const STATUS_COLORS: Record<string, string> = {
  pending: 'gold',
  reviewed: 'blue',
  dismissed: 'default',
  action_taken: 'green',
};

export function ReportQueuePage() {
  const [page, setPage] = useState(1);
  const [limit, setLimit] = useState(20);
  const [selected, setSelected] = useState<ReportResponse | null>(null);

  const { data, isPending, isError, error, refetch, isFetching } = useReportsList({ page, limit });

  const columns: ColumnsType<ReportResponse> = [
    { title: 'Reason', dataIndex: 'reason' },
    {
      title: 'Status',
      dataIndex: 'status',
      render: (value: string) => <Tag color={STATUS_COLORS[value] ?? 'default'}>{value}</Tag>,
    },
    {
      title: 'Submitted',
      dataIndex: 'created_at',
      render: (value: string) => new Date(value).toLocaleString(),
    },
  ];

  if (isError) return <ErrorState error={error} onRetry={refetch} />;

  return (
    <div>
      <Typography.Title level={3} style={{ marginTop: 0 }}>
        Reports queue
      </Typography.Title>

      <Table<ReportResponse>
        rowKey="id"
        columns={columns}
        dataSource={data?.rows ?? []}
        loading={isPending || isFetching}
        onRow={(row) => ({ onClick: () => setSelected(row), style: { cursor: 'pointer' } })}
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

      <ReportDetailDrawer report={selected} onClose={() => setSelected(null)} />
    </div>
  );
}
