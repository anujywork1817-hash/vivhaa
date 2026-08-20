import { CheckOutlined, CloseOutlined } from '@ant-design/icons';
import { Button, Descriptions, Drawer, Image, Input, Modal, Space, Typography, message } from 'antd';
import { useState } from 'react';
import { ErrorState } from '../../components/ErrorState';
import { LoadingState } from '../../components/LoadingState';
import { useUser } from '../../hooks/useUsers';
import { useApproveVerification, useRejectVerification } from '../../hooks/useVerifications';
import type { VerificationResponse } from '../../types/api';

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
    <Drawer title="Review ID verification" width={640} open={open} onClose={onClose} destroyOnClose>
      {isPending && <LoadingState label="Loading applicant…" />}
      {isError && <ErrorState error={error} onRetry={refetch} />}
      {verification && user && (
        <Space direction="vertical" size="large" style={{ width: '100%' }}>
          <div>
            <Typography.Text strong>Submitted document ({verification.document_type})</Typography.Text>
            <div style={{ marginTop: 8 }}>
              <Image src={verification.document_url} alt="ID document" style={{ maxWidth: '100%', borderRadius: 6 }} />
            </div>
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
