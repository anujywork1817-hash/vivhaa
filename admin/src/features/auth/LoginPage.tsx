import { LockOutlined, UserOutlined } from '@ant-design/icons';
import { Alert, Button, Card, Form, Input, Typography } from 'antd';
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

interface LoginFormValues {
  identifier: string;
  password: string;
}

export function LoginPage() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(values: LoginFormValues) {
    setSubmitting(true);
    setError(null);
    try {
      await login(values.identifier, values.password);
      navigate('/', { replace: true });
    } catch (err) {
      // Covers both "wrong credentials" (backend 401) and "valid
      // credentials, not an admin" (thrown client-side in AuthContext)
      // with one consistent error surface.
      setError(messageFor(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#F5F6F8',
      }}
    >
      <Card style={{ width: 380 }}>
        <Typography.Title level={3} style={{ marginBottom: 4 }}>
          Vivaha Admin
        </Typography.Title>
        <Typography.Text type="secondary">Sign in with your admin account</Typography.Text>

        {error && <Alert type="error" message={error} showIcon style={{ marginTop: 20 }} />}

        <Form<LoginFormValues> layout="vertical" onFinish={handleSubmit} style={{ marginTop: 24 }}>
          <Form.Item
            name="identifier"
            label="Phone or email"
            rules={[{ required: true, message: 'Enter your phone number or email' }]}
          >
            <Input prefix={<UserOutlined />} placeholder="+91XXXXXXXXXX or you@example.com" autoFocus />
          </Form.Item>
          <Form.Item name="password" label="Password" rules={[{ required: true, message: 'Enter your password' }]}>
            <Input.Password prefix={<LockOutlined />} placeholder="Password" />
          </Form.Item>
          <Form.Item style={{ marginBottom: 0 }}>
            <Button type="primary" htmlType="submit" block loading={submitting}>
              Sign in
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  );
}

function messageFor(err: unknown): string {
  if (err instanceof Error && err.message) return err.message;
  return 'Could not sign in. Check your credentials and try again.';
}
