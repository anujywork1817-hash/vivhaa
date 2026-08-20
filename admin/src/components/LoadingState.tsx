import { Spin } from 'antd';

export function LoadingState({ label = 'Loading…' }: { label?: string }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '64px 0', gap: 12 }}>
      <Spin size="large" />
      <span style={{ color: '#8c8c8c' }}>{label}</span>
    </div>
  );
}
