import { ArrowLeftOutlined, StopOutlined, CheckCircleOutlined, FileOutlined } from '@ant-design/icons';
import { Avatar, Button, Card, Descriptions, Image, List, Modal, Space, Tag, Typography, message } from 'antd';
import { useNavigate, useParams } from 'react-router-dom';
import { ErrorState } from '../../components/ErrorState';
import { LoadingState } from '../../components/LoadingState';
import { useActivateUser, useSuspendUser, useUser } from '../../hooks/useUsers';
import { useUserDocuments } from '../../hooks/useVerifications';
import type { VerificationResponse } from '../../types/api';

const STATUS_COLORS: Record<string, string> = { active: 'green', pending: 'gold', suspended: 'red' };

const DOC_STATUS_COLORS: Record<string, string> = { approved: 'green', rejected: 'red', pending: 'gold' };

const DOC_TYPE_LABELS: Record<string, string> = {
  aadhaar: 'Aadhaar',
  passport: 'Passport',
  driving_license: 'Driving License',
  voter_id: 'Voter ID',
  pan: 'PAN',
  selfie: 'Selfie',
  personal_document: 'Personal Document',
};

function isImageUrl(url: string): boolean {
  return /\.(png|jpe?g|gif|webp|bmp|heic|heif)(\?|$)/i.test(url);
}

// document_url comes straight from the API into <Image src>/<a href> with
// no scheme check — normally always the app's own S3/CDN URL, but if that
// assumption is ever broken (a compromised upload pipeline, e.g.), an
// unvalidated javascript:/data: URI could execute in this admin session's
// authenticated origin the moment someone clicks "View / download
// document". Only http(s) is ever a legitimate document link.
function isSafeHttpUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

export function UserDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: user, isPending, isError, error, refetch } = useUser(id);
  const { data: documents, isPending: documentsPending } = useUserDocuments(id);
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
        try {
          await suspend.mutateAsync(id as string);
          message.success('User suspended.');
        } catch {
          // Without this, a failed request (network error, 403, 500) just
          // silently closed the modal with no feedback — the admin had no
          // way to tell the suspend didn't actually happen.
          message.error('Could not suspend this user. Please try again.');
        }
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
        try {
          await activate.mutateAsync(id as string);
          message.success('User activated.');
        } catch {
          message.error('Could not activate this user. Please try again.');
        }
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

      <Card title="Documents">
        {documentsPending ? (
          <LoadingState label="Loading documents…" />
        ) : documents && documents.length > 0 ? (
          <List
            itemLayout="horizontal"
            dataSource={documents}
            renderItem={(doc: VerificationResponse) => (
              <List.Item>
                <List.Item.Meta
                  avatar={
                    isSafeHttpUrl(doc.document_url) && isImageUrl(doc.document_url) ? (
                      <Image
                        src={doc.document_url}
                        alt={doc.document_type}
                        width={56}
                        height={56}
                        style={{ objectFit: 'cover', borderRadius: 4 }}
                        fallback="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI1NiIgaGVpZ2h0PSI1NiI+PC9zdmc+"
                      />
                    ) : (
                      <FileOutlined style={{ fontSize: 32, color: '#8c8c8c' }} />
                    )
                  }
                  title={
                    <Space>
                      <span>{DOC_TYPE_LABELS[doc.document_type] ?? doc.document_type}</span>
                      <Tag color={DOC_STATUS_COLORS[doc.status] ?? 'default'}>{doc.status}</Tag>
                    </Space>
                  }
                  description={
                    <Space direction="vertical" size={0}>
                      <span>Submitted {new Date(doc.created_at).toLocaleString()}</span>
                      {doc.reviewed_at && <span>Reviewed {new Date(doc.reviewed_at).toLocaleString()}</span>}
                      {doc.review_notes && <span>Notes: {doc.review_notes}</span>}
                      {isSafeHttpUrl(doc.document_url) ? (
                        <a href={doc.document_url} target="_blank" rel="noreferrer">
                          View / download document
                        </a>
                      ) : (
                        <span style={{ color: '#8c8c8c' }}>Document link unavailable</span>
                      )}
                    </Space>
                  }
                />
              </List.Item>
            )}
          />
        ) : (
          <Typography.Text type="secondary">No documents submitted yet.</Typography.Text>
        )}
      </Card>
    </div>
  );
}
