import { Button, Result } from 'antd';
import { isAxiosError } from 'axios';
import type { Envelope } from '../types/api';

// Reused everywhere an API call can fail — never leaves the admin
// staring at a blank screen with no explanation or way forward.
export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const message = extractMessage(error);
  return (
    <Result
      status="error"
      title="Something went wrong"
      subTitle={message}
      extra={
        onRetry && (
          <Button type="primary" onClick={onRetry}>
            Try again
          </Button>
        )
      }
    />
  );
}

function extractMessage(error: unknown): string {
  if (isAxiosError<Envelope<unknown>>(error)) {
    const backendMessage = error.response?.data?.error?.message;
    if (backendMessage) return backendMessage;
    if (error.response?.status === 403) return "You don't have permission to do this.";
    if (!error.response) return 'Could not reach the server. Check your connection and try again.';
  }
  if (error instanceof Error) return error.message;
  return 'An unexpected error occurred.';
}
