import { Card, Statistic } from 'antd';
import type { ReactNode } from 'react';

export function MetricCard({
  title,
  value,
  prefix,
  valueColor,
}: {
  title: string;
  value: number | string;
  prefix?: ReactNode;
  valueColor?: string;
}) {
  return (
    <Card>
      <Statistic
        title={title}
        value={value}
        prefix={prefix}
        styles={valueColor ? { content: { color: valueColor } } : undefined}
      />
    </Card>
  );
}
