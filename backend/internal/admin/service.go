package admin

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/storage"
	"matrimony-backend/internal/subscriptions"
	"matrimony-backend/internal/unlock"
	"matrimony-backend/internal/verification"
)

const (
	defaultLimit = 20
	maxLimit     = 100
	// exportLimit is the row cap for a CSV export — a de facto ceiling on
	// how large a single export can get, not a real pagination limit;
	// nothing in this codebase currently approaches it.
	exportLimit = 50000
)

type Service struct {
	repo             *Repository
	profilesRepo     *profiles.Repository
	subsRepo         *subscriptions.Repository
	verificationRepo *verification.Repository
	docUploader      *storage.DocumentUploader
	unlockService    *unlock.Service
}

func NewService(repo *Repository, profilesRepo *profiles.Repository, subsRepo *subscriptions.Repository, verificationRepo *verification.Repository, docUploader *storage.DocumentUploader, unlockService *unlock.Service) *Service {
	return &Service{repo: repo, profilesRepo: profilesRepo, subsRepo: subsRepo, verificationRepo: verificationRepo, docUploader: docUploader, unlockService: unlockService}
}

func (s *Service) ListUsers(ctx context.Context, f ListUsersFilter) ([]UserResponse, ListUsersMeta, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.Limit < 1 {
		f.Limit = defaultLimit
	}
	if f.Limit > maxLimit {
		f.Limit = maxLimit
	}

	users, total, err := s.repo.ListUsers(ctx, f)
	if err != nil {
		return nil, ListUsersMeta{}, err
	}

	out := make([]UserResponse, 0, len(users))
	for _, u := range users {
		out = append(out, toUserResponse(u))
	}
	return out, ListUsersMeta{Page: f.Page, Limit: f.Limit, Total: total}, nil
}

func (s *Service) GetUser(ctx context.Context, id string) (UserDetailResponse, error) {
	u, err := s.repo.GetUserByID(ctx, id)
	if err != nil {
		return UserDetailResponse{}, err
	}

	profileSummary, err := s.getProfileSummary(ctx, id)
	if err != nil {
		return UserDetailResponse{}, err
	}
	subSummary, err := s.getSubscriptionSummary(ctx, id)
	if err != nil {
		return UserDetailResponse{}, err
	}
	verifSummary, err := s.getVerificationSummary(ctx, id)
	if err != nil {
		return UserDetailResponse{}, err
	}

	return UserDetailResponse{
		UserResponse: toUserResponse(u),
		Profile:      profileSummary,
		Subscription: subSummary,
		Verification: verifSummary,
	}, nil
}

// getProfileSummary looks up userID's profile for display purposes only
// (name, age, city, photo) — nil, not an error, when the account never
// completed onboarding.
func (s *Service) getProfileSummary(ctx context.Context, userID string) (*ProfileSummary, error) {
	p, err := s.profilesRepo.GetByUserID(ctx, userID)
	if errors.Is(err, profiles.ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	var age *int
	if p.DateOfBirth != nil {
		a := int(time.Since(*p.DateOfBirth).Hours() / 24 / 365.25)
		age = &a
	}

	var photoURL *string
	photos, err := s.profilesRepo.ListPhotos(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	for _, photo := range photos {
		if photo.IsPrimary {
			url := photo.URL
			photoURL = &url
			break
		}
	}
	if photoURL == nil && len(photos) > 0 {
		url := photos[0].URL
		photoURL = &url
	}

	return &ProfileSummary{
		FullName:    p.FullName,
		Age:         age,
		Gender:      p.Gender,
		City:        p.City,
		State:       p.State,
		Occupation:  p.Occupation,
		ProfileCode: p.ProfileCode,
		PhotoURL:    photoURL,
	}, nil
}

// getSubscriptionSummary reports userID's current active, non-expired
// plan — nil (not an error) when they're on the free tier, mirroring
// subscriptions.Service.GetMine's own definition of "active."
func (s *Service) getSubscriptionSummary(ctx context.Context, userID string) (*SubscriptionSummary, error) {
	sub, err := s.subsRepo.GetActiveByUserID(ctx, userID)
	if errors.Is(err, subscriptions.ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	plan, err := s.subsRepo.GetPlanByID(ctx, sub.PlanID)
	if err != nil {
		return nil, err
	}
	if plan.Code == "free" {
		return nil, nil
	}

	var endsAt *string
	if sub.EndsAt != nil {
		v := sub.EndsAt.Format(time.RFC3339)
		endsAt = &v
	}
	return &SubscriptionSummary{PlanCode: plan.Code, PlanName: plan.Name, EndsAt: endsAt}, nil
}

// getVerificationSummary reports userID's most recent ID-document
// submission — nil (not an error) when they've never submitted one.
func (s *Service) getVerificationSummary(ctx context.Context, userID string) (*VerificationSummary, error) {
	v, err := s.verificationRepo.GetLatestByUserID(ctx, userID)
	if errors.Is(err, verification.ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	var reviewedAt *string
	if v.ReviewedAt != nil {
		s := v.ReviewedAt.Format(time.RFC3339)
		reviewedAt = &s
	}
	// BUG-C06: document lives in a private bucket now — mint a fresh
	// short-lived signed URL rather than trusting anything stored in the
	// DB (v.DocumentURL is legacy/stale, never read).
	//
	// BUG-M02: a presign failure here (transient S3 hiccup, a missing
	// object) used to fail the whole GetUser call, which blocked an
	// admin from viewing or suspending an account over nothing more
	// than a thumbnail not loading. Degrading to an empty DocumentURL
	// lets the rest of the page — and every admin action on it — work
	// regardless.
	docURL, err := s.docUploader.PresignURL(ctx, v.DocumentKey)
	if err != nil {
		slog.Default().Warn("presign verification document url failed",
			"user_id", userID, "verification_id", v.ID, "error", err)
		docURL = ""
	}
	return &VerificationSummary{
		Status:       v.Status,
		DocumentType: v.DocumentType,
		DocumentURL:  docURL,
		ReviewNotes:  v.ReviewNotes,
		ReviewedAt:   reviewedAt,
	}, nil
}

func (s *Service) Suspend(ctx context.Context, id string) (UserResponse, error) {
	u, err := s.repo.UpdateUserStatus(ctx, id, "suspended")
	if err != nil {
		return UserResponse{}, err
	}
	return toUserResponse(u), nil
}

func (s *Service) Activate(ctx context.Context, id string) (UserResponse, error) {
	u, err := s.repo.UpdateUserStatus(ctx, id, "active")
	if err != nil {
		return UserResponse{}, err
	}
	return toUserResponse(u), nil
}

func (s *Service) GetDashboard(ctx context.Context) (DashboardResponse, error) {
	d, err := s.repo.GetDashboard(ctx)
	if err != nil {
		return DashboardResponse{}, err
	}
	return DashboardResponse{
		TotalUsers:           d.TotalUsers,
		ActiveUsers:          d.ActiveUsers,
		SuspendedUsers:       d.SuspendedUsers,
		NewSignupsToday:      d.NewSignupsToday,
		TotalMatches:         d.TotalMatches,
		TotalMessages:        d.TotalMessages,
		PendingVerifications: d.PendingVerifications,
		PendingReports:       d.PendingReports,
		ActiveSubscriptions:  d.ActiveSubscriptions,
		RevenueINR:           d.RevenueINR,
		UnlockRevenueINR:     d.UnlockRevenueINR,
		TotalRevenueINR:      d.RevenueINR + d.UnlockRevenueINR,
	}, nil
}

type ListSubscriptionsFilter struct {
	Status *string
	Page   int
	Limit  int
}

func (s *Service) ListSubscriptions(ctx context.Context, f ListSubscriptionsFilter) ([]SubscriptionRowResponse, ListUsersMeta, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.Limit < 1 {
		f.Limit = defaultLimit
	}
	if f.Limit > maxLimit {
		f.Limit = maxLimit
	}

	rows, total, err := s.repo.ListSubscriptions(ctx, f.Status, f.Limit, (f.Page-1)*f.Limit)
	if err != nil {
		return nil, ListUsersMeta{}, err
	}

	out := make([]SubscriptionRowResponse, 0, len(rows))
	for _, r := range rows {
		var startsAt, endsAt *string
		if r.StartsAt != nil {
			v := r.StartsAt.Format(time.RFC3339)
			startsAt = &v
		}
		if r.EndsAt != nil {
			v := r.EndsAt.Format(time.RFC3339)
			endsAt = &v
		}
		out = append(out, SubscriptionRowResponse{
			ID: r.ID, UserID: r.UserID, Phone: r.Phone, Email: r.Email, FullName: r.FullName,
			PlanCode: r.PlanCode, PlanName: r.PlanName, Status: r.Status,
			StartsAt: startsAt, EndsAt: endsAt,
		})
	}
	return out, ListUsersMeta{Page: f.Page, Limit: f.Limit, Total: total}, nil
}

type ListUnlockAccountsFilter struct {
	Status *string
	Page   int
	Limit  int
}

// ListUnlockAccounts is ListSubscriptions' counterpart for the ₹1 unlock
// gate — every account that has attempted or completed that one-time
// payment, not the plan-based subscription system.
func (s *Service) ListUnlockAccounts(ctx context.Context, f ListUnlockAccountsFilter) ([]UnlockAccountRowResponse, ListUsersMeta, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.Limit < 1 {
		f.Limit = defaultLimit
	}
	if f.Limit > maxLimit {
		f.Limit = maxLimit
	}

	rows, total, err := s.repo.ListUnlockAccounts(ctx, f.Status, f.Limit, (f.Page-1)*f.Limit)
	if err != nil {
		return nil, ListUsersMeta{}, err
	}

	out := make([]UnlockAccountRowResponse, 0, len(rows))
	for _, r := range rows {
		out = append(out, toUnlockAccountRowResponse(r))
	}
	return out, ListUsersMeta{Page: f.Page, Limit: f.Limit, Total: total}, nil
}

func toUnlockAccountRowResponse(r UnlockAccountRow) UnlockAccountRowResponse {
	var paidAt *string
	if r.PaidAt != nil {
		v := r.PaidAt.Format(time.RFC3339)
		paidAt = &v
	}
	return UnlockAccountRowResponse{
		ID: r.ID, UserID: r.UserID, Phone: r.Phone, Email: r.Email, FullName: r.FullName,
		AmountINR: r.AmountINR, Currency: r.Currency, Status: r.Status,
		CreatedAt: r.CreatedAt.Format(time.RFC3339), PaidAt: paidAt,
	}
}

// GetUnlockRevenueSummary reports the ₹1 unlock gate's own headline
// numbers, kept separate from GetRevenue/GetDashboard's plan-based
// figures — paid/created/failed counts make this a conversion funnel,
// not just a revenue total.
func (s *Service) GetUnlockRevenueSummary(ctx context.Context) (UnlockRevenueSummaryResponse, error) {
	paid, created, failed, revenue, err := s.repo.GetUnlockRevenueSummary(ctx)
	if err != nil {
		return UnlockRevenueSummaryResponse{}, err
	}
	return UnlockRevenueSummaryResponse{
		TotalPaidAccounts:    paid,
		TotalCreatedAccounts: created,
		TotalFailedAccounts:  failed,
		TotalRevenueINR:      revenue,
	}, nil
}

// GetUserFinance is one user's full money history across both payment
// systems — used by the User Detail page's Finance card so a support
// agent doesn't have to cross-reference the separate Subscriptions and
// Accounts list pages to answer "did this person actually pay?".
func (s *Service) GetUserFinance(ctx context.Context, userID string) (UserFinanceResponse, error) {
	unlockRows, err := s.repo.GetUnlockPaymentsForUser(ctx, userID)
	if err != nil {
		return UserFinanceResponse{}, err
	}
	paymentRows, err := s.repo.GetPaymentsForUser(ctx, userID)
	if err != nil {
		return UserFinanceResponse{}, err
	}

	unlockOut := make([]UnlockAccountRowResponse, 0, len(unlockRows))
	for _, r := range unlockRows {
		unlockOut = append(unlockOut, toUnlockAccountRowResponse(r))
	}

	paymentsOut := make([]PaymentRowResponse, 0, len(paymentRows))
	for _, p := range paymentRows {
		var paidAt *string
		if p.PaidAt != nil {
			v := p.PaidAt.Format(time.RFC3339)
			paidAt = &v
		}
		paymentsOut = append(paymentsOut, PaymentRowResponse{
			ID: p.ID, PlanName: p.PlanName, AmountINR: p.AmountINR, DiscountINR: p.DiscountINR,
			Currency: p.Currency, Status: p.Status, CreatedAt: p.CreatedAt.Format(time.RFC3339), PaidAt: paidAt,
		})
	}

	return UserFinanceResponse{UnlockPayments: unlockOut, Payments: paymentsOut}, nil
}

// ReconcileUnlockPayments delegates to the unlock package's own
// reconciliation sweep — kept there (rather than duplicated here) since
// it's the package that owns the Razorpay gateway and the finalize/
// mark-unlocked transaction logic; admin is just the trigger.
func (s *Service) ReconcileUnlockPayments(ctx context.Context) (unlock.ReconcileResponse, error) {
	return s.unlockService.Reconcile(ctx)
}

// ExportSubscriptionsRows fetches every subscription row (up to
// exportLimit), optionally filtered by status, for CSV export — same
// query ListSubscriptions uses, just without pagination.
func (s *Service) ExportSubscriptionsRows(ctx context.Context, status *string) ([]SubscriptionRow, error) {
	rows, _, err := s.repo.ListSubscriptions(ctx, status, exportLimit, 0)
	return rows, err
}

// ExportUnlockAccountsRows is ExportSubscriptionsRows' counterpart for
// the ₹1 unlock gate.
func (s *Service) ExportUnlockAccountsRows(ctx context.Context, status *string) ([]UnlockAccountRow, error) {
	rows, _, err := s.repo.ListUnlockAccounts(ctx, status, exportLimit, 0)
	return rows, err
}

// trustSafetyListLimit caps each of the three lists in GetTrustSafety —
// this is a "worst offenders at a glance" view, not a paginated browse.
const trustSafetyListLimit = 25

// GetTrustSafety assembles every aggregate abuse signal this admin panel
// surfaces — see TrustSafetyResponse's doc comment.
func (s *Service) GetTrustSafety(ctx context.Context) (TrustSafetyResponse, error) {
	reported, err := s.repo.GetMostReportedUsers(ctx, trustSafetyListLimit)
	if err != nil {
		return TrustSafetyResponse{}, err
	}
	blocked, err := s.repo.GetMostBlockedUsers(ctx, trustSafetyListLimit)
	if err != nil {
		return TrustSafetyResponse{}, err
	}
	// Capped generously above the list limit: this counts raw
	// (token, account) rows, not groups, and a handful of large groups
	// could otherwise starve out smaller ones before they're even seen.
	deviceRows, err := s.repo.GetSharedDeviceGroups(ctx, trustSafetyListLimit*10)
	if err != nil {
		return TrustSafetyResponse{}, err
	}

	reportedOut := make([]ReportedUserRowResponse, 0, len(reported))
	for _, r := range reported {
		reportedOut = append(reportedOut, ReportedUserRowResponse{
			UserID: r.UserID, Phone: r.Phone, Email: r.Email, FullName: r.FullName,
			ReportCount: r.ReportCount, LastReportedAt: r.LastReportedAt.Format(time.RFC3339),
		})
	}

	blockedOut := make([]BlockedUserRowResponse, 0, len(blocked))
	for _, b := range blocked {
		blockedOut = append(blockedOut, BlockedUserRowResponse{
			UserID: b.UserID, Phone: b.Phone, Email: b.Email, FullName: b.FullName, BlockCount: b.BlockCount,
		})
	}

	// Group the flat (token, account) rows back into one entry per
	// token, preserving the query's per-token ordering.
	order := make([]string, 0, trustSafetyListLimit)
	groups := make(map[string][]AccountBriefResponse)
	for _, row := range deviceRows {
		if _, seen := groups[row.Token]; !seen {
			order = append(order, row.Token)
		}
		a := row.Account
		groups[row.Token] = append(groups[row.Token], AccountBriefResponse{
			UserID: a.UserID, Phone: a.Phone, Email: a.Email, FullName: a.FullName,
		})
	}
	deviceOut := make([]SharedDeviceGroupResponse, 0, len(order))
	for _, token := range order {
		if len(deviceOut) >= trustSafetyListLimit {
			break
		}
		deviceOut = append(deviceOut, SharedDeviceGroupResponse{Token: token, Accounts: groups[token]})
	}

	return TrustSafetyResponse{MostReported: reportedOut, MostBlocked: blockedOut, SharedDevices: deviceOut}, nil
}

// GetRevenue combines the by-plan and by-month breakdowns into one
// response — the same "paid, net of discount" figure as GetDashboard's
// RevenueINR, just sliced two ways for the revenue chart.
func (s *Service) GetRevenue(ctx context.Context) (RevenueResponse, error) {
	byPlan, err := s.repo.GetRevenueByPlan(ctx)
	if err != nil {
		return RevenueResponse{}, err
	}
	byMonth, err := s.repo.GetRevenueByMonth(ctx)
	if err != nil {
		return RevenueResponse{}, err
	}

	var total int64
	planRows := make([]RevenueByPlanRow, 0, len(byPlan))
	for _, p := range byPlan {
		total += p.RevenueINR
		planRows = append(planRows, RevenueByPlanRow{
			PlanCode: p.PlanCode, PlanName: p.PlanName, RevenueINR: p.RevenueINR, PaymentsCount: p.PaymentsCount,
		})
	}
	monthRows := make([]RevenueByMonthRow, 0, len(byMonth))
	for _, m := range byMonth {
		monthRows = append(monthRows, RevenueByMonthRow{Month: m.Month, RevenueINR: m.RevenueINR})
	}

	return RevenueResponse{TotalINR: total, ByPlan: planRows, ByMonth: monthRows}, nil
}

func toUserResponse(u User) UserResponse {
	var lastLogin *string
	if u.LastLoginAt != nil {
		v := u.LastLoginAt.Format(time.RFC3339)
		lastLogin = &v
	}
	return UserResponse{
		ID:            u.ID,
		Phone:         u.Phone,
		Email:         u.Email,
		PhoneVerified: u.PhoneVerified,
		EmailVerified: u.EmailVerified,
		Status:        u.Status,
		Role:          u.Role,
		LastLoginAt:   lastLogin,
		CreatedAt:     u.CreatedAt.Format(time.RFC3339),
	}
}
