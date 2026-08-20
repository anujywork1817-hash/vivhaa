// Every type here mirrors a real Go struct in matrimony_backend 1:1 —
// field names/optionality intentionally match the JSON tags exactly
// (internal/auth/dto.go, internal/admin/dto.go, internal/verification/dto.go,
// internal/moderation/dto.go) so a backend response shape change surfaces
// here as a compile error instead of a silently-wrong UI.

// pkg/response.Envelope — the shape every API response is wrapped in.
export interface Envelope<T> {
  success: boolean;
  data: T;
  error?: { code: string; message: string; details?: unknown };
  meta?: unknown;
}

export interface PagedEnvelope<T> extends Envelope<T[]> {
  meta: ListMeta;
}

// internal/admin.ListUsersMeta (reused as-is by verification.ListMeta,
// moderation.ListMeta, and admin's subscriptions listing — identical shape).
export interface ListMeta {
  page: number;
  limit: number;
  total: number;
}

// --- Auth (internal/auth/dto.go) ---

export interface UserBrief {
  id: string;
  phone: string | null;
  email: string | null;
  role: string;
}

export interface AuthResponse {
  access_token: string;
  refresh_token: string;
  expires_at: string;
  user: UserBrief;
}

// --- Admin: users (internal/admin/dto.go) ---

export interface UserResponse {
  id: string;
  phone: string | null;
  email: string | null;
  phone_verified: boolean;
  email_verified: boolean;
  status: string; // pending | active | suspended
  role: string; // user | admin
  last_login_at: string | null;
  created_at: string;
}

export interface ProfileSummary {
  full_name: string | null;
  age: number | null;
  gender: string | null;
  city: string | null;
  state: string | null;
  occupation: string | null;
  profile_code: string;
  photo_url: string | null;
}

export interface SubscriptionSummary {
  plan_code: string;
  plan_name: string;
  ends_at: string | null;
}

export interface VerificationSummary {
  status: string;
  document_type: string;
  document_url: string;
  review_notes: string | null;
  reviewed_at: string | null;
}

// GET /admin/users/:id — UserResponse's fields, flattened, plus context.
export interface UserDetailResponse extends UserResponse {
  profile: ProfileSummary | null;
  subscription: SubscriptionSummary | null;
  verification: VerificationSummary | null;
}

// --- Admin: dashboard ---

export interface DashboardResponse {
  total_users: number;
  active_users: number;
  suspended_users: number;
  new_signups_today: number;
  total_matches: number;
  total_messages: number;
  pending_verifications: number;
  pending_reports: number;
  active_subscriptions: number;
  revenue_inr: number;
}

// --- Admin: subscriptions & revenue ---

export interface SubscriptionRowResponse {
  id: string;
  user_id: string;
  phone: string | null;
  email: string | null;
  full_name: string | null;
  plan_code: string;
  plan_name: string;
  status: string;
  starts_at: string | null;
  ends_at: string | null;
}

export interface RevenueByPlanRow {
  plan_code: string;
  plan_name: string;
  revenue_inr: number;
  payments_count: number;
}

export interface RevenueByMonthRow {
  month: string; // "YYYY-MM"
  revenue_inr: number;
}

export interface RevenueResponse {
  total_inr: number;
  by_plan: RevenueByPlanRow[];
  by_month: RevenueByMonthRow[];
}

// --- Verification queue (internal/verification/dto.go) ---

export interface VerificationResponse {
  id: string;
  user_id: string;
  document_type: string;
  document_url: string;
  status: string; // pending | approved | rejected
  review_notes: string | null;
  created_at: string;
  reviewed_at: string | null;
}

export interface ReviewRequest {
  notes?: string;
}

// --- Reports / moderation queue (internal/moderation/dto.go) ---

export interface ReportResponse {
  id: string;
  reporter_user_id: string;
  reported_user_id: string;
  reason: string;
  details: string | null;
  status: string; // pending | reviewed | dismissed | action_taken
  review_notes: string | null;
  created_at: string;
  reviewed_at: string | null;
}

export interface ResolveRequest {
  status: 'reviewed' | 'dismissed' | 'action_taken';
  notes?: string;
  suspend_user: boolean;
}

// --- Call history (internal/calls/dto.go) ---

export interface CallHistoryResponse {
  id: string;
  caller_user_id: string;
  caller_name: string | null;
  callee_user_id: string;
  callee_name: string | null;
  status: string; // initiated | ongoing | completed | missed | rejected | failed
  is_video: boolean;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number | null;
  end_reason: string | null;
}
