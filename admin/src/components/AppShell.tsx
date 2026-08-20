import {
  DashboardOutlined,
  DollarOutlined,
  FlagOutlined,
  LogoutOutlined,
  PhoneOutlined,
  SafetyCertificateOutlined,
  UserOutlined,
} from '@ant-design/icons';
import { Avatar, Dropdown, Layout, Menu, Space, Typography } from 'antd';
import { useMemo } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

const { Sider, Header, Content } = Layout;

const NAV_ITEMS = [
  { key: '/', icon: <DashboardOutlined />, label: 'Dashboard' },
  { key: '/users', icon: <UserOutlined />, label: 'Users' },
  { key: '/verifications', icon: <SafetyCertificateOutlined />, label: 'Verifications' },
  { key: '/reports', icon: <FlagOutlined />, label: 'Reports' },
  { key: '/subscriptions', icon: <DollarOutlined />, label: 'Subscriptions & Revenue' },
  { key: '/call-history', icon: <PhoneOutlined />, label: 'Call History' },
];

export function AppShell() {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, logout } = useAuth();

  // Highlights the nav item for the current section even on a detail
  // route like /users/:id, which isn't itself a nav item.
  const selectedKey = useMemo(() => {
    const match = NAV_ITEMS.filter((item) => item.key !== '/' && location.pathname.startsWith(item.key));
    if (match.length > 0) return match[0].key;
    return location.pathname === '/' ? '/' : '';
  }, [location.pathname]);

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider width={232} theme="dark">
        <div
          style={{
            height: 56,
            display: 'flex',
            alignItems: 'center',
            paddingLeft: 20,
            color: '#fff',
            fontWeight: 600,
            fontSize: 16,
            letterSpacing: 0.3,
          }}
        >
          Vivaha Admin
        </div>
        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[selectedKey]}
          items={NAV_ITEMS}
          onClick={({ key }) => navigate(key)}
        />
      </Sider>
      <Layout>
        <Header
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'flex-end',
            padding: '0 24px',
            borderBottom: '1px solid #EAECEF',
          }}
        >
          <Dropdown
            menu={{
              items: [{ key: 'logout', icon: <LogoutOutlined />, label: 'Sign out' }],
              onClick: async ({ key }) => {
                if (key === 'logout') {
                  await logout();
                  navigate('/login', { replace: true });
                }
              },
            }}
            placement="bottomRight"
          >
            <Space style={{ cursor: 'pointer' }}>
              <Avatar size="small" icon={<UserOutlined />} />
              <Typography.Text>{user?.phone ?? user?.email ?? 'Admin'}</Typography.Text>
            </Space>
          </Dropdown>
        </Header>
        <Content style={{ margin: 24 }}>
          <Outlet />
        </Content>
      </Layout>
    </Layout>
  );
}
