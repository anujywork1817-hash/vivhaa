import {
  DollarOutlined,
  FlagOutlined,
  MessageOutlined,
  SafetyCertificateOutlined,
  TeamOutlined,
  UserAddOutlined,
} from '@ant-design/icons';
import { Col, Row, Typography } from 'antd';
import { ErrorState } from '../../components/ErrorState';
import { LoadingState } from '../../components/LoadingState';
import { useDashboard } from '../../hooks/useDashboard';
import { MetricCard } from './MetricCard';
import { QuickLinkCard } from './QuickLinkCard';

export function DashboardPage() {
  const { data, isPending, isError, error, refetch } = useDashboard();

  if (isPending) return <LoadingState label="Loading dashboard…" />;
  if (isError) return <ErrorState error={error} onRetry={refetch} />;

  return (
    <div>
      <Typography.Title level={3} style={{ marginTop: 0 }}>
        Dashboard
      </Typography.Title>

      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12} lg={8} xl={6}>
          <MetricCard title="Total users" value={data.total_users} prefix={<TeamOutlined />} />
        </Col>
        <Col xs={24} sm={12} lg={8} xl={6}>
          <MetricCard title="Active users" value={data.active_users} prefix={<TeamOutlined />} valueColor="#389e0d" />
        </Col>
        <Col xs={24} sm={12} lg={8} xl={6}>
          <MetricCard title="Suspended users" value={data.suspended_users} valueColor="#cf1322" />
        </Col>
        <Col xs={24} sm={12} lg={8} xl={6}>
          <MetricCard title="New signups today" value={data.new_signups_today} prefix={<UserAddOutlined />} />
        </Col>
        <Col xs={24} sm={12} lg={8} xl={6}>
          <MetricCard title="Active matches" value={data.total_matches} />
        </Col>
        <Col xs={24} sm={12} lg={8} xl={6}>
          <MetricCard title="Messages sent" value={data.total_messages} prefix={<MessageOutlined />} />
        </Col>
        <Col xs={24} sm={12} lg={8} xl={6}>
          <MetricCard title="Active subscriptions" value={data.active_subscriptions} />
        </Col>
        <Col xs={24} sm={12} lg={8} xl={6}>
          <MetricCard
            title="Total revenue"
            value={`₹${data.revenue_inr.toLocaleString('en-IN')}`}
            prefix={<DollarOutlined />}
          />
        </Col>
      </Row>

      <Typography.Title level={4} style={{ marginTop: 32 }}>
        Review queues
      </Typography.Title>
      <Row gutter={[16, 16]}>
        <Col xs={24} sm={12}>
          <QuickLinkCard
            title="Verification queue"
            pendingCount={data.pending_verifications}
            icon={<SafetyCertificateOutlined style={{ fontSize: 20 }} />}
            to="/verifications"
          />
        </Col>
        <Col xs={24} sm={12}>
          <QuickLinkCard
            title="Reports queue"
            pendingCount={data.pending_reports}
            icon={<FlagOutlined style={{ fontSize: 20 }} />}
            to="/reports"
          />
        </Col>
      </Row>
    </div>
  );
}
