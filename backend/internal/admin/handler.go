package admin

import (
	"encoding/csv"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) ListUsers(c *gin.Context) {
	var f ListUsersFilter
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	if v := c.Query("role"); v != "" {
		f.Role = &v
	}
	if v := c.Query("search"); v != "" {
		f.Search = &v
	}
	f.Page, _ = strconv.Atoi(c.Query("page"))
	f.Limit, _ = strconv.Atoi(c.Query("limit"))

	users, meta, err := h.service.ListUsers(c.Request.Context(), f)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.Success(c, http.StatusOK, users, meta)
}

func (h *Handler) GetUser(c *gin.Context) {
	resp, err := h.service.GetUser(c.Request.Context(), c.Param("id"))
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "user not found", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Suspend(c *gin.Context) {
	resp, err := h.service.Suspend(c.Request.Context(), c.Param("id"))
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "user not found", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Activate(c *gin.Context) {
	resp, err := h.service.Activate(c.Request.Context(), c.Param("id"))
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "user not found", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Dashboard(c *gin.Context) {
	resp, err := h.service.GetDashboard(c.Request.Context())
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) ListSubscriptions(c *gin.Context) {
	var f ListSubscriptionsFilter
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	f.Page, _ = strconv.Atoi(c.Query("page"))
	f.Limit, _ = strconv.Atoi(c.Query("limit"))

	rows, meta, err := h.service.ListSubscriptions(c.Request.Context(), f)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.Success(c, http.StatusOK, rows, meta)
}

func (h *Handler) Revenue(c *gin.Context) {
	resp, err := h.service.GetRevenue(c.Request.Context())
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) ListUnlockAccounts(c *gin.Context) {
	var f ListUnlockAccountsFilter
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	f.Page, _ = strconv.Atoi(c.Query("page"))
	f.Limit, _ = strconv.Atoi(c.Query("limit"))

	rows, meta, err := h.service.ListUnlockAccounts(c.Request.Context(), f)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.Success(c, http.StatusOK, rows, meta)
}

func (h *Handler) UnlockRevenueSummary(c *gin.Context) {
	resp, err := h.service.GetUnlockRevenueSummary(c.Request.Context())
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) UserFinance(c *gin.Context) {
	resp, err := h.service.GetUserFinance(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

// ReconcileUnlockAccounts is a POST-triggered admin action (not a passive
// list endpoint), since it makes outbound Razorpay calls and can mutate
// unlock_payments rows — see Service.ReconcileUnlockPayments.
func (h *Handler) ReconcileUnlockAccounts(c *gin.Context) {
	resp, err := h.service.ReconcileUnlockPayments(c.Request.Context())
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

// ExportSubscriptionsCSV streams every subscription row (optionally
// filtered by status) as a CSV attachment — a direct browser navigation
// (e.g. window.open) triggers a download the same way any other file
// download would, no JS-side blob handling required.
func (h *Handler) ExportSubscriptionsCSV(c *gin.Context) {
	var status *string
	if v := c.Query("status"); v != "" {
		status = &v
	}
	rows, err := h.service.ExportSubscriptionsRows(c.Request.Context(), status)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}

	c.Header("Content-Type", "text/csv")
	c.Header("Content-Disposition", `attachment; filename="subscriptions.csv"`)
	w := csv.NewWriter(c.Writer)
	_ = w.Write([]string{"id", "user_id", "phone", "email", "full_name", "plan_code", "plan_name", "status", "starts_at", "ends_at"})
	for _, r := range rows {
		_ = w.Write([]string{
			r.ID, r.UserID, derefOr(r.Phone, ""), derefOr(r.Email, ""), derefOr(r.FullName, ""),
			r.PlanCode, r.PlanName, r.Status, formatTimeOr(r.StartsAt, ""), formatTimeOr(r.EndsAt, ""),
		})
	}
	w.Flush()
}

// ExportUnlockAccountsCSV is ExportSubscriptionsCSV's counterpart for the
// ₹1 unlock gate.
func (h *Handler) ExportUnlockAccountsCSV(c *gin.Context) {
	var status *string
	if v := c.Query("status"); v != "" {
		status = &v
	}
	rows, err := h.service.ExportUnlockAccountsRows(c.Request.Context(), status)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}

	c.Header("Content-Type", "text/csv")
	c.Header("Content-Disposition", `attachment; filename="unlock-accounts.csv"`)
	w := csv.NewWriter(c.Writer)
	_ = w.Write([]string{"id", "user_id", "phone", "email", "full_name", "amount_inr", "currency", "status", "created_at", "paid_at"})
	for _, r := range rows {
		_ = w.Write([]string{
			r.ID, r.UserID, derefOr(r.Phone, ""), derefOr(r.Email, ""), derefOr(r.FullName, ""),
			fmt.Sprintf("%d", r.AmountINR), r.Currency, r.Status, r.CreatedAt.Format(csvTimeLayout), formatTimeOr(r.PaidAt, ""),
		})
	}
	w.Flush()
}

func (h *Handler) TrustSafety(c *gin.Context) {
	resp, err := h.service.GetTrustSafety(c.Request.Context())
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

const csvTimeLayout = "2006-01-02 15:04:05"

func derefOr(s *string, fallback string) string {
	if s == nil {
		return fallback
	}
	return *s
}

func formatTimeOr(t *time.Time, fallback string) string {
	if t == nil {
		return fallback
	}
	return t.Format(csvTimeLayout)
}
