import { Alert, Button, Checkbox, Descriptions, Drawer, Input, Modal, Select, Space, Typography, message } from 'antd';
import { useState } from 'react';
import { ErrorState } from '../../components/ErrorState';
import { LoadingState } from '../../components/LoadingState';
import { useUser } from '../../hooks/useUsers';
import { useResolveReport } from '../../hooks/useReports';
import type { ReportResponse, ResolveRequest } from '../../types/api';

export function ReportDetailDrawer({ report, onClose }: { report: ReportResponse | null; onClose: () => void }) {
  const [status, setStatus] = useState<ResolveRequest['status']>('reviewed');
  const [notes, setNotes] = useState('');
  const [suspendUser, setSuspendUser] = useState(false);

  const { data: reporter } = useUser(report?.reporter_user_id);
  const { data: reported, isPending, isError, error, refetch } = useUser(report?.reported_user_id);
  const resolve = useResolveReport();

  const open = !!report;

  function reset() {
    setStatus('reviewed');
    setNotes('');
    setSuspendUser(false);
  }

  function handleResolve() {
    if (!report) return;
    const req: ResolveRequest = { status, notes: notes || undefined, suspend_user: suspendUser };

    // Confirmation is mandatory whenever this resolve would also suspend
    // the reported user — a real, immediate consequence for their
    // account, not just a queue-bookkeeping change like "reviewed".
    if (suspendUser) {
      Modal.confirm({
        title: 'Resolve and suspend this user?',
        content: 'They will immediately lose access to the app. This does not delete their data.',
        okText: 'Resolve & suspend',
        okButtonProps: { danger: true },
        onOk: async () => {
          try {
            await resolve.mutateAsync({ id: report.id, req });
            message.success('Report resolved and user suspended.');
            reset();
            onClose();
          } catch {
            // Without this, a failed suspend-via-report action gave the
            // admin no feedback at all — the drawer just stayed open with
            // no indication anything went wrong.
            message.error('Could not resolve this report. Please try again.');
          }
        },
      });
      return;
    }

    resolve.mutate(
      { id: report.id, req },
      {
        onSuccess: () => {
          message.success('Report resolved.');
          reset();
          onClose();
        },
        onError: () => {
          message.error('Could not resolve this report. Please try again.');
        },
      },
    );
  }

  return (
    <Drawer title="Review report" width={640} open={open} onClose={onClose} destroyOnClose>
      {isPending && <LoadingState label="Loading report context…" />}
      {isError && <ErrorState error={error} onRetry={refetch} />}
      {report && reported && (
        <Space direction="vertical" size="large" style={{ width: '100%' }}>
          <Descriptions column={1} size="small" title="Report">
            <Descriptions.Item label="Reason">{report.reason}</Descriptions.Item>
            {report.details && <Descriptions.Item label="Details">{report.details}</Descriptions.Item>}
            <Descriptions.Item label="Reported by">{reporter?.phone ?? reporter?.email ?? report.reporter_user_id}</Descriptions.Item>
            <Descriptions.Item label="Submitted">{new Date(report.created_at).toLocaleString()}</Descriptions.Item>
          </Descriptions>

          <div>
            <Typography.Text strong>Reported user</Typography.Text>
            <Descriptions column={1} size="small" style={{ marginTop: 8 }}>
              <Descriptions.Item label="Name">{reported.profile?.full_name ?? '—'}</Descriptions.Item>
              <Descriptions.Item label="Profile ID">{reported.profile?.profile_code ?? '—'}</Descriptions.Item>
              <Descriptions.Item label="Contact">{reported.phone ?? reported.email ?? '—'}</Descriptions.Item>
              <Descriptions.Item label="Account status">{reported.status}</Descriptions.Item>
            </Descriptions>
            {reported.status === 'suspended' && (
              <Alert type="info" showIcon message="This user is already suspended." style={{ marginTop: 8 }} />
            )}
          </div>

          <div>
            <Typography.Text strong>Resolution</Typography.Text>
            <Space direction="vertical" style={{ width: '100%', marginTop: 8 }}>
              <Select<ResolveRequest['status']>
                value={status}
                onChange={setStatus}
                style={{ width: '100%' }}
                options={[
                  { value: 'reviewed', label: 'Reviewed — no action needed' },
                  { value: 'dismissed', label: 'Dismissed — not a violation' },
                  { value: 'action_taken', label: 'Action taken' },
                ]}
              />
              <Input.TextArea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} placeholder="Internal notes (optional)" />
              <Checkbox checked={suspendUser} onChange={(e) => setSuspendUser(e.target.checked)} disabled={reported.status === 'suspended'}>
                Suspend the reported user
              </Checkbox>
            </Space>
          </div>

          <Button type="primary" danger={suspendUser} loading={resolve.isPending} onClick={handleResolve}>
            {suspendUser ? 'Resolve & suspend' : 'Resolve report'}
          </Button>
        </Space>
      )}
    </Drawer>
  );
}
