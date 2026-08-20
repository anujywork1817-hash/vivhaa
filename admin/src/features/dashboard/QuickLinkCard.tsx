import { ArrowRightOutlined } from '@ant-design/icons';
import { Badge, Card, Space, Typography } from 'antd';
import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';

export function QuickLinkCard({
  title,
  pendingCount,
  icon,
  to,
}: {
  title: string;
  pendingCount: number;
  icon: ReactNode;
  to: string;
}) {
  const navigate = useNavigate();
  return (
    <Card hoverable onClick={() => navigate(to)}>
      <Space align="center" style={{ width: '100%', justifyContent: 'space-between' }}>
        <Space>
          {icon}
          <div>
            <Typography.Text strong>{title}</Typography.Text>
            <div>
              <Typography.Text type="secondary">{pendingCount} pending</Typography.Text>
            </div>
          </div>
        </Space>
        <Space>
          {pendingCount > 0 && <Badge count={pendingCount} overflowCount={99} />}
          <ArrowRightOutlined />
        </Space>
      </Space>
    </Card>
  );
}
