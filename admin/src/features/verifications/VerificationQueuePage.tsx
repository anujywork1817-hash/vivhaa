import { Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { useState } from 'react';
import { ErrorState } from '../../components/ErrorState';
import { useVerificationsList } from '../../hooks/useVerifications';
import type { VerificationResponse } from '../../types/api';
import { documentLabel, VerificationDetailDrawer } from './VerificationDetailDrawer';

export function VerificationQueuePage() {
  const [page, setPage] = useState(1);
  const [limit, setLimit] = useState(20);
  const [selected, setSelected] = useState<VerificationResponse | null>(null);

  const { data, isPending, isError, error, refetch, isFetching } = useVerificationsList({ page, limit });

  const columns: ColumnsType<VerificationResponse> = [
    { title: 'Document type', dataIndex: 'document_type', render: (value: string) => documentLabel(value) },
    {
      title: 'Status',
      dataIndex: 'status',
      render: (value: string) => <Tag color="gold">{value}</Tag>,
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
        Verification queue
      </Typography.Title>

      <Table<VerificationResponse>
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

      <VerificationDetailDrawer verification={selected} onClose={() => setSelected(null)} />
    </div>
  );
}
