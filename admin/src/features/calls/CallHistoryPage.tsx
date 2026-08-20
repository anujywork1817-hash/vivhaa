import { DatePicker, Select, Space, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import dayjs, { type Dayjs } from 'dayjs';
import { useState } from 'react';
import { ErrorState } from '../../components/ErrorState';
import { useCallHistoryList } from '../../hooks/useCalls';
import type { CallHistoryResponse } from '../../types/api';

const { RangePicker } = DatePicker;

const STATUS_COLORS: Record<string, string> = {
  completed: 'green',
  ongoing: 'blue',
  initiated: 'gold',
  missed: 'default',
  rejected: 'orange',
  failed: 'red',
};

function formatDuration(seconds: number | null): string {
  if (seconds === null) return '—';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

// Read-only for moderation/support — the admin panel never places or
// joins a call itself, it only ever looks at internal/calls' record of
// what already happened.
export function CallHistoryPage() {
  const [status, setStatus] = useState<string | undefined>(undefined);
  const [dateRange, setDateRange] = useState<[Dayjs, Dayjs] | null>(null);
  const [page, setPage] = useState(1);
  const [limit, setLimit] = useState(20);

  const { data, isPending, isError, error, refetch, isFetching } = useCallHistoryList({
    status,
    from: dateRange?.[0]?.format('YYYY-MM-DD'),
    to: dateRange?.[1]?.format('YYYY-MM-DD'),
    page,
    limit,
  });

  const columns: ColumnsType<CallHistoryResponse> = [
    { title: 'Caller', key: 'caller', render: (_, row) => row.caller_name ?? row.caller_user_id },
    { title: 'Callee', key: 'callee', render: (_, row) => row.callee_name ?? row.callee_user_id },
    {
      title: 'Status',
      dataIndex: 'status',
      render: (value: string) => <Tag color={STATUS_COLORS[value] ?? 'default'}>{value}</Tag>,
    },
    {
      title: 'Type',
      dataIndex: 'is_video',
      render: (value: boolean) => <Tag color={value ? 'purple' : 'cyan'}>{value ? 'Video' : 'Voice'}</Tag>,
    },
    { title: 'Duration', dataIndex: 'duration_seconds', render: formatDuration },
    {
      title: 'Started',
      dataIndex: 'started_at',
      render: (value: string) => new Date(value).toLocaleString(),
    },
    {
      title: 'End reason',
      dataIndex: 'end_reason',
      render: (value: string | null) => value ?? '—',
    },
  ];

  return (
    <div>
      <Typography.Title level={3} style={{ marginTop: 0 }}>
        Call History
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
                { value: 'completed', label: 'Completed' },
                { value: 'ongoing', label: 'Ongoing' },
                { value: 'initiated', label: 'Initiated' },
                { value: 'missed', label: 'Missed' },
                { value: 'rejected', label: 'Rejected' },
                { value: 'failed', label: 'Failed' },
              ]}
            />
            <RangePicker
              value={dateRange}
              onChange={(dates) => {
                setDateRange(dates && dates[0] && dates[1] ? [dates[0], dates[1]] : null);
                setPage(1);
              }}
              disabledDate={(d) => d.isAfter(dayjs())}
            />
          </Space>

          <Table<CallHistoryResponse>
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
