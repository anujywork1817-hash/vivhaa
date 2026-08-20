import { ArrowLeftOutlined, StopOutlined, CheckCircleOutlined } from '@ant-design/icons';
import { Avatar, Button, Card, Descriptions, Modal, Space, Tag, Typography, message } from 'antd';
import { useNavigate, useParams } from 'react-router-dom';
import { ErrorState } from '../../components/ErrorState';
import { LoadingState } from '../../components/LoadingState';
import { useActivateUser, useSuspendUser, useUser } from '../../hooks/useUsers';

const STATUS_COLORS: Record<string, string> = { active: 'green', pending: 'gold', suspended: 'red' };

export function UserDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: user, isPending, isError, error, refetch } = useUser(id);
  const suspend = useSuspendUser();
  const activate = useActivateUser();

  if (isPending) return <LoadingState label="Loading user…" />;
  if (isError) return <ErrorState error={error} onRetry={refetch} />;

  function confirmSuspend() {
    Modal.confirm({
      title: 'Suspend this user?',
      icon: <StopOutlined style={{ color: '#cf1322' }} />,
      content: 'They will immediately lose access to the app until reactivated. This does not delete their data.',
      okText: 'Suspend',
      okButtonProps: { danger: true },
      onOk: async () => {
        await suspend.mutateAsync(id as string);
        message.success('User suspended.');
      },
    });
  }

  function confirmActivate() {
    Modal.confirm({
      title: 'Reactivate this user?',
      icon: <CheckCircleOutlined style={{ color: '#389e0d' }} />,
      content: 'They will regain full access to the app.',
      okText: 'Activate',
      onOk: async () => {
        await activate.mutateAsync(id as string);
        message.success('User activated.');
      },
    });
  }

  return (
    <div>
      <Button icon={<ArrowLeftOutlined />} type="text" onClick={() => navigate('/users')} style={{ marginBottom: 12 }}>
        Back to users
      </Button>

      <Space align="start" style={{ width: '100%', justifyContent: 'space-between', marginBottom: 16 }} wrap>
        <Space align="center" size="large">
          <Avatar size={64} src={user.profile?.photo_url ?? undefined}>
            {(user.profile?.full_name ?? user.phone ?? user.email ?? '?').charAt(0).toUpperCase()}
          </Avatar>
          <div>
            <Typography.Title level={3} style={{ margin: 0 }}>
              {user.profile?.full_name ?? user.phone ?? user.email ?? 'Unnamed user'}
            </Typography.Title>
            <Tag color={STATUS_COLORS[user.status] ?? 'default'}>{user.status}</Tag>
            {user.role === 'admin' && <Tag color="blue">admin</Tag>}
          </div>
        </Space>
        <Space>
          {user.status === 'suspended' ? (
            <Button type="primary" icon={<CheckCircleOutlined />} loading={activate.isPending} onClick={confirmActivate}>
              Activate
            </Button>
          ) : (
            <Button danger icon={<StopOutlined />} loading={suspend.isPending} onClick={confirmSuspend}>
              Suspend
            </Button>
          )}
        </Space>
      </Space>

      <Card title="Account" style={{ marginBottom: 16 }}>
        <Descriptions column={2} size="small">
          <Descriptions.Item label="Phone">{user.phone ?? '—'}</Descriptions.Item>
          <Descriptions.Item label="Email">{user.email ?? '—'}</Descriptions.Item>
          <Descriptions.Item label="Phone verified">{user.phone_verified ? 'Yes' : 'No'}</Descriptions.Item>
          <Descriptions.Item label="Email verified">{user.email_verified ? 'Yes' : 'No'}</Descriptions.Item>
          <Descriptions.Item label="Joined">{new Date(user.created_at).toLocaleString()}</Descriptions.Item>
          <Descriptions.Item label="Last login">
            {user.last_login_at ? new Date(user.last_login_at).toLocaleString() : 'Never'}
          </Descriptions.Item>
        </Descriptions>
      </Card>

      <Card title="Profile" style={{ marginBottom: 16 }}>
        {user.profile ? (
          <Descriptions column={2} size="small">
            <Descriptions.Item label="Name">{user.profile.full_name ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="Profile ID">{user.profile.profile_code}</Descriptions.Item>
            <Descriptions.Item label="Age">{user.profile.age ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="Gender">{user.profile.gender ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="City">{user.profile.city ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="State">{user.profile.state ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="Occupation">{user.profile.occupation ?? '—'}</Descriptions.Item>
          </Descriptions>
        ) : (
          <Typography.Text type="secondary">This account never completed onboarding — no profile yet.</Typography.Text>
        )}
      </Card>

      <Card title="Subscription" style={{ marginBottom: 16 }}>
        {user.subscription ? (
          <Descriptions column={2} size="small">
            <Descriptions.Item label="Plan">{user.subscription.plan_name}</Descriptions.Item>
            <Descriptions.Item label="Expires">
              {user.subscription.ends_at ? new Date(user.subscription.ends_at).toLocaleDateString() : '—'}
            </Descriptions.Item>
          </Descriptions>
        ) : (
          <Typography.Text type="secondary">Free tier — no active subscription.</Typography.Text>
        )}
      </Card>

      <Card title="Verification">
        {user.verification ? (
          <Descriptions column={2} size="small">
            <Descriptions.Item label="Status">
              <Tag color={user.verification.status === 'approved' ? 'green' : user.verification.status === 'rejected' ? 'red' : 'gold'}>
                {user.verification.status}
              </Tag>
            </Descriptions.Item>
            <Descriptions.Item label="Document type">{user.verification.document_type}</Descriptions.Item>
            <Descriptions.Item label="Submitted document" span={2}>
              <a href={user.verification.document_url} target="_blank" rel="noreferrer">
                View document
              </a>
            </Descriptions.Item>
            {user.verification.review_notes && (
              <Descriptions.Item label="Review notes" span={2}>
                {user.verification.review_notes}
              </Descriptions.Item>
            )}
          </Descriptions>
        ) : (
          <Typography.Text type="secondary">No ID document submitted yet.</Typography.Text>
        )}
      </Card>
    </div>
  );
}
