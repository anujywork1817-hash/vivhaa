import { Card, Col, Row, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { Link } from 'react-router-dom';
import { ErrorState } from '../../components/ErrorState';
import { LoadingState } from '../../components/LoadingState';
import { useTrustSafety } from '../../hooks/useTrustSafety';
import type { AccountBriefResponse, BlockedUserRowResponse, ReportedUserRowResponse, SharedDeviceGroupResponse } from '../../types/api';

function accountLabel(a: { phone: string | null; email: string | null; full_name: string | null }): string {
  return a.full_name ?? a.phone ?? a.email ?? '—';
}

// Trust & Safety surfaces aggregate abuse patterns no other admin screen
// shows: the Reports/Verification queues both work one submission at a
// time, so "this exact account has been reported by 6 different people"
// or "these 3 accounts all register from the same device" is invisible
// unless something aggregates across the whole user base — that's all
// this page does.
export function TrustSafetyPage() {
  const { data, isPending, isError, error, refetch } = useTrustSafety();

  if (isPending) return <LoadingState label="Loading trust & safety signals…" />;
  if (isError) return <ErrorState error={error} onRetry={refetch} />;

  const reportedColumns: ColumnsType<ReportedUserRowResponse> = [
    {
      title: 'User',
      key: 'user',
      render: (_, row) => <Link to={`/users/${row.user_id}`}>{accountLabel(row)}</Link>,
    },
    {
      title: 'Reports',
      dataIndex: 'report_count',
      render: (value: number) => <Tag color={value >= 3 ? 'red' : 'gold'}>{value}</Tag>,
      sorter: (a, b) => a.report_count - b.report_count,
      defaultSortOrder: 'descend',
    },
    {
      title: 'Last reported',
      dataIndex: 'last_reported_at',
      render: (value: string) => new Date(value).toLocaleString(),
    },
  ];

  const blockedColumns: ColumnsType<BlockedUserRowResponse> = [
    {
      title: 'User',
      key: 'user',
      render: (_, row) => <Link to={`/users/${row.user_id}`}>{accountLabel(row)}</Link>,
    },
    {
      title: 'Times blocked',
      dataIndex: 'block_count',
      render: (value: number) => <Tag color={value >= 3 ? 'red' : 'gold'}>{value}</Tag>,
      sorter: (a, b) => a.block_count - b.block_count,
      defaultSortOrder: 'descend',
    },
  ];

  const deviceColumns: ColumnsType<SharedDeviceGroupResponse> = [
    {
      title: 'Accounts sharing this device',
      key: 'accounts',
      render: (_, row) => (
        <Typography.Text>
          {row.accounts.map((a: AccountBriefResponse, i: number) => (
            <span key={a.user_id}>
              {i > 0 && ', '}
              <Link to={`/users/${a.user_id}`}>{accountLabel(a)}</Link>
            </span>
          ))}
        </Typography.Text>
      ),
    },
    {
      title: 'Account count',
      key: 'count',
      render: (_, row) => <Tag color={row.accounts.length >= 3 ? 'red' : 'gold'}>{row.accounts.length}</Tag>,
      sorter: (a, b) => a.accounts.length - b.accounts.length,
      defaultSortOrder: 'descend',
    },
  ];

  return (
    <div>
      <Typography.Title level={3} style={{ marginTop: 0 }}>
        Trust & Safety
      </Typography.Title>
      <Typography.Paragraph type="secondary">
        Aggregate abuse signals across the whole user base — none of these are automatic verdicts, just patterns
        worth a closer look.
      </Typography.Paragraph>

      <Row gutter={[16, 16]}>
        <Col xs={24} lg={12}>
          <Card title="Most reported accounts" style={{ height: '100%' }}>
            <Table<ReportedUserRowResponse>
              size="small"
              rowKey="user_id"
              columns={reportedColumns}
              dataSource={data.most_reported}
              pagination={false}
              locale={{ emptyText: 'No reports filed yet.' }}
            />
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="Most blocked accounts" style={{ height: '100%' }}>
            <Table<BlockedUserRowResponse>
              size="small"
              rowKey="user_id"
              columns={blockedColumns}
              dataSource={data.most_blocked}
              pagination={false}
              locale={{ emptyText: 'No one has been blocked yet.' }}
            />
          </Card>
        </Col>
      </Row>

      <Card
        title="Accounts sharing a device"
        style={{ marginTop: 16 }}
        extra={
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            Same push-notification token registered to 2+ accounts — could be family sharing a phone, or one
            operator running multiple fake profiles.
          </Typography.Text>
        }
      >
        <Table<SharedDeviceGroupResponse>
          size="small"
          rowKey="token"
          columns={deviceColumns}
          dataSource={data.shared_devices}
          pagination={false}
          locale={{ emptyText: 'No device is currently shared across accounts.' }}
        />
      </Card>
    </div>
  );
}
