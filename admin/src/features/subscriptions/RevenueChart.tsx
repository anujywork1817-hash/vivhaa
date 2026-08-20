import { Card, Col, Row, Statistic, Typography } from 'antd';
import { Bar, BarChart, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { ErrorState } from '../../components/ErrorState';
import { LoadingState } from '../../components/LoadingState';
import { useRevenue } from '../../hooks/useSubscriptions';

const formatINR = (value: number) => `₹${value.toLocaleString('en-IN')}`;

export function RevenueChart() {
  const { data, isPending, isError, error, refetch } = useRevenue();

  if (isPending) return <LoadingState label="Loading revenue…" />;
  if (isError) return <ErrorState error={error} onRetry={refetch} />;

  return (
    <div>
      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        <Col xs={24} sm={8}>
          <Card>
            <Statistic title="Total revenue (all time)" value={data.total_inr} formatter={(v) => formatINR(Number(v))} />
          </Card>
        </Col>
      </Row>

      <Row gutter={[16, 16]}>
        <Col xs={24} lg={12}>
          <Card title="Revenue by plan">
            {data.by_plan.length === 0 ? (
              <Typography.Text type="secondary">No paid payments yet.</Typography.Text>
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <BarChart data={data.by_plan}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} />
                  <XAxis dataKey="plan_name" tick={{ fontSize: 12 }} />
                  <YAxis tickFormatter={formatINR} width={80} tick={{ fontSize: 12 }} />
                  <Tooltip formatter={(v) => formatINR(Number(v))} />
                  <Bar dataKey="revenue_inr" fill="#3457D5" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="Revenue by month (trailing 12 months)">
            {data.by_month.length === 0 ? (
              <Typography.Text type="secondary">No paid payments yet.</Typography.Text>
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <LineChart data={data.by_month}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} />
                  <XAxis dataKey="month" tick={{ fontSize: 12 }} />
                  <YAxis tickFormatter={formatINR} width={80} tick={{ fontSize: 12 }} />
                  <Tooltip formatter={(v) => formatINR(Number(v))} />
                  <Line type="monotone" dataKey="revenue_inr" stroke="#3457D5" strokeWidth={2} dot={{ r: 3 }} />
                </LineChart>
              </ResponsiveContainer>
            )}
          </Card>
        </Col>
      </Row>
    </div>
  );
}
