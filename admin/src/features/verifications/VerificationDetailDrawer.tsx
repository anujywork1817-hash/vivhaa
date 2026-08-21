import { CheckOutlined, CloseOutlined } from '@ant-design/icons';
import { Button, Descriptions, Drawer, Empty, Image, Input, Modal, Space, Tag, Typography, message } from 'antd';
import { useState } from 'react';
import { ErrorState } from '../../components/ErrorState';
import { LoadingState } from '../../components/LoadingState';
import { useUser } from '../../hooks/useUsers';
import { useApproveVerification, useRejectVerification, useUserDocuments } from '../../hooks/useVerifications';
import type { VerificationResponse } from '../../types/api';

export const DOCUMENT_LABELS: Record<string, string> = {
  aadhaar: 'Aadhaar card',
  passport: 'Passport',
  driving_license: 'Driving license',
  voter_id: 'Voter ID',
  pan: 'PAN card',
  selfie: 'Verification selfie',
  personal_document: 'Personal document',
};

export function documentLabel(type: string): string {
  return DOCUMENT_LABELS[type] ?? type;
}

const STATUS_COLORS: Record<string, string> = {
  pending: 'gold',
  approved: 'green',
  rejected: 'red',
};

/// One applicant's full set of uploaded documents — the selfie next to the
/// ID next to whatever else they submitted — so approving an Aadhaar
/// actually means comparing it against the face in the selfie, which is
/// the entire point of the two-document flow. The queue used to open a
/// drawer scoped to the single pending row that was clicked, with no way
/// to see anything else the applicant uploaded.
function ApplicantDocuments({ userId, highlightId }: { userId: string; highlightId: string }) {
  const { data: documents, isPending, isError, error, refetch } = useUserDocuments(userId);

  if (isPending) return <LoadingState label="Loading documents…" />;
  if (isError) return <ErrorState error={error} onRetry={refetch} />;
  if (!documents || documents.length === 0) {
    return <Empty description="No documents on file" />;
  }

  return (
    <Image.PreviewGroup>
      <Space direction="vertical" size="middle" style={{ width: '100%' }}>
        {documents.map((doc) => (
          <div
            key={doc.id}
            style={
              doc.id === highlightId
                ? { padding: 8, margin: -8, border: '2px solid #1677ff', borderRadius: 8 }
                : undefined
            }
          >
            <Space align="center" style={{ marginBottom: 8 }}>
              <Typography.Text strong>{documentLabel(doc.document_type)}</Typography.Text>
              <Tag color={STATUS_COLORS[doc.status] ?? 'default'}>{doc.status}</Tag>
              {doc.id === highlightId && <Tag color="blue">Under review</Tag>}
            </Space>
            <div>
              <Image
                src={doc.document_url}
                alt={documentLabel(doc.document_type)}
                style={{ maxWidth: '100%', maxHeight: 320, borderRadius: 6, objectFit: 'contain' }}
              />
            </div>
            <Typography.Text type="secondary" style={{ fontSize: 12 }}>
              Submitted {new Date(doc.created_at).toLocaleString()}
            </Typography.Text>
          </div>
        ))}
      </Space>
    </Image.PreviewGroup>
  );
}

export function VerificationDetailDrawer({
  verification,
  onClose,
}: {
  verification: VerificationResponse | null;
  onClose: () => void;
}) {
  const [notes, setNotes] = useState('');
  const { data: user, isPending, isError, error, refetch } = useUser(verification?.user_id);
  const approve = useApproveVerification();
  const reject = useRejectVerification();

  const open = !!verification;

  async function handleApprove() {
    if (!verification) return;
    await approve.mutateAsync({ id: verification.id, req: { notes: notes || undefined } });
    message.success('Verification approved.');
    setNotes('');
    onClose();
  }

  function confirmReject() {
    if (!verification) return;
    Modal.confirm({
      title: 'Reject this verification?',
      content: 'The applicant will need to resubmit a document to get verified.',
      okText: 'Reject',
      okButtonProps: { danger: true },
      onOk: async () => {
        await reject.mutateAsync({ id: verification.id, req: { notes: notes || undefined } });
        message.success('Verification rejected.');
        setNotes('');
        onClose();
      },
    });
  }

  return (
    <Drawer
      title={verification ? `Review ${documentLabel(verification.document_type)}` : 'Review verification'}
      width={640}
      open={open}
      onClose={onClose}
      destroyOnClose
    >
      {isPending && <LoadingState label="Loading applicant…" />}
      {isError && <ErrorState error={error} onRetry={refetch} />}
      {verification && user && (
        <Space direction="vertical" size="large" style={{ width: '100%' }}>
          <div>
            <Typography.Text strong>Uploaded documents</Typography.Text>
            <Typography.Paragraph type="secondary" style={{ marginTop: 4, marginBottom: 8 }}>
              Every document this applicant has submitted, so the ID can be checked against the selfie. Click a
              photo to zoom.
            </Typography.Paragraph>
            <ApplicantDocuments userId={verification.user_id} highlightId={verification.id} />
          </div>

          <div>
            <Typography.Text strong>Applicant profile</Typography.Text>
            <Descriptions column={1} size="small" style={{ marginTop: 8 }}>
              <Descriptions.Item label="Name">{user.profile?.full_name ?? '—'}</Descriptions.Item>
              <Descriptions.Item label="Profile ID">{user.profile?.profile_code ?? '—'}</Descriptions.Item>
              <Descriptions.Item label="Contact">{user.phone ?? user.email ?? '—'}</Descriptions.Item>
              <Descriptions.Item label="City / State">
                {[user.profile?.city, user.profile?.state].filter(Boolean).join(', ') || '—'}
              </Descriptions.Item>
              <Descriptions.Item label="Submitted">{new Date(verification.created_at).toLocaleString()}</Descriptions.Item>
            </Descriptions>
          </div>

          <div>
            <Typography.Text strong>Review notes (optional)</Typography.Text>
            <Input.TextArea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={3}
              placeholder="Visible to the applicant if rejected"
              style={{ marginTop: 8 }}
            />
          </div>

          <Space>
            <Button
              type="primary"
              icon={<CheckOutlined />}
              loading={approve.isPending}
              disabled={reject.isPending}
              onClick={handleApprove}
            >
              Approve
            </Button>
            <Button danger icon={<CloseOutlined />} loading={reject.isPending} disabled={approve.isPending} onClick={confirmReject}>
              Reject
            </Button>
          </Space>
        </Space>
      )}
    </Drawer>
  );
}
