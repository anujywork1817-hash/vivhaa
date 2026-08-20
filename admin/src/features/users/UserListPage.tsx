import { SearchOutlined } from '@ant-design/icons';
import { Input, Select, Space, Table, Tag, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ErrorState } from '../../components/ErrorState';
import { useUsersList } from '../../hooks/useUsers';
import type { UserResponse } from '../../types/api';

const STATUS_COLORS: Record<string, string> = {
  active: 'green',
  pending: 'gold',
  suspended: 'red',
};

export function UserListPage() {
  const navigate = useNavigate();
  const [status, setStatus] = useState<string | undefined>();
  const [role, setRole] = useState<string | undefined>();
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [limit, setLimit] = useState(20);

  const { data, isPending, isError, error, refetch, isFetching } = useUsersList({
    status,
    role,
    search: search || undefined,
    page,
    limit,
  });

  const columns: ColumnsType<UserResponse> = [
    {
      title: 'Contact',
      key: 'contact',
      render: (_, row) => row.phone ?? row.email ?? '—',
    },
    {
      title: 'Status',
      dataIndex: 'status',
      render: (value: string) => <Tag color={STATUS_COLORS[value] ?? 'default'}>{value}</Tag>,
    },
    { title: 'Role', dataIndex: 'role' },
    {
      title: 'Verified',
      key: 'verified',
      render: (_, row) => (row.phone_verified || row.email_verified ? 'Yes' : 'No'),
    },
    {
      title: 'Joined',
      dataIndex: 'created_at',
      render: (value: string) => new Date(value).toLocaleDateString(),
    },
  ];

  if (isError) return <ErrorState error={error} onRetry={refetch} />;

  return (
    <div>
      <Typography.Title level={3} style={{ marginTop: 0 }}>
        Users
      </Typography.Title>

      <Space style={{ marginBottom: 16 }} wrap>
        <Input
          placeholder="Search phone or email"
          prefix={<SearchOutlined />}
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(1);
          }}
          allowClear
          style={{ width: 260 }}
        />
        <Select
          placeholder="Status"
          allowClear
          style={{ width: 160 }}
          value={status}
          onChange={(v) => {
            setStatus(v);
            setPage(1);
          }}
          options={[
            { value: 'active', label: 'Active' },
            { value: 'pending', label: 'Pending' },
            { value: 'suspended', label: 'Suspended' },
          ]}
        />
        <Select
          placeholder="Role"
          allowClear
          style={{ width: 160 }}
          value={role}
          onChange={(v) => {
            setRole(v);
            setPage(1);
          }}
          options={[
            { value: 'user', label: 'User' },
            { value: 'admin', label: 'Admin' },
          ]}
        />
      </Space>

      <Table<UserResponse>
        rowKey="id"
        columns={columns}
        dataSource={data?.rows ?? []}
        loading={isPending || isFetching}
        onRow={(row) => ({ onClick: () => navigate(`/users/${row.id}`), style: { cursor: 'pointer' } })}
        pagination={{
          current: page,
          pageSize: limit,
          total: data?.meta.total ?? 0,
          showSizeChanger: true,
          onChange: (p, ps) => {
            setPage(p);
            setLimit(ps);
          },
        }}
      />
    </div>
  );
}
