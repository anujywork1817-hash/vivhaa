package payments

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/coupons"
	"matrimony-backend/pkg/response"
	"matrimony-backend/pkg/validator"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) Checkout(c *gin.Context) {
	var req CheckoutRequest
	if !bindAndValidate(c, &req) {
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.Checkout(c.Request.Context(), userID, req)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) Verify(c *gin.Context) {
	var req VerifyRequest
	if !bindAndValidate(c, &req) {
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.Verify(c.Request.Context(), userID, req)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

// webhookEvent is the slice of Razorpay's webhook payload this handler
// actually needs. Razorpay sends many event types (order.paid,
// payment.failed, refund.*, ...); only payment.captured triggers
// activation here.
type webhookEvent struct {
	Event   string `json:"event"`
	Payload struct {
		Payment struct {
			Entity struct {
				ID       string `json:"id"`
				OrderID  string `json:"order_id"`
				Amount   int64  `json:"amount"`
				Currency string `json:"currency"`
				Status   string `json:"status"`
			} `json:"entity"`
		} `json:"payment"`
	} `json:"payload"`
}

// Webhook is Razorpay calling us directly (server-to-server) — no user
// session, so it's authenticated via X-Razorpay-Signature instead of a
// Bearer token (see routes.go, which mounts this outside RequireAuth).
// This is the belt-and-suspenders activation path: it doesn't depend on
// the client successfully calling /verify, so a payment that captures
// but whose client never completes the round trip (crash, closed app,
// lost network) still gets its subscription activated.
func (h *Handler) Webhook(c *gin.Context) {
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "could not read request body", nil)
		return
	}

	if !h.service.VerifyWebhookSignature(body, c.GetHeader("X-Razorpay-Signature")) {
		response.Fail(c, http.StatusUnauthorized, "invalid_webhook_signature", "webhook signature verification failed", nil)
		return
	}

	var evt webhookEvent
	if err := json.Unmarshal(body, &evt); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "malformed webhook payload", nil)
		return
	}

	if evt.Event != "payment.captured" {
		// Ack anyway so Razorpay doesn't keep retrying a delivery there's
		// nothing for us to act on (order.paid, payment.failed, refunds, …).
		response.OK(c, gin.H{"handled": false})
		return
	}

	p := evt.Payload.Payment.Entity
	err = h.service.ActivateFromWebhook(c.Request.Context(), p.OrderID, p.ID, p.Amount, p.Currency, p.Status)
	switch {
	case err == nil:
		response.OK(c, gin.H{"handled": true})
	case errors.Is(err, ErrNotFound):
		// order_id doesn't match any payment we created — ack anyway,
		// retrying this delivery won't change that.
		response.OK(c, gin.H{"handled": false})
	default:
		// 500 so Razorpay retries per its webhook redelivery policy —
		// swallowing this would silently drop an activation with no
		// recovery path, exactly what this endpoint exists to prevent.
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}

// mockCompleteRequest/MockComplete: dev-only, see routes.go — only
// registered when the mock gateway is active.
type mockCompleteRequest struct {
	OrderID string `json:"razorpay_order_id" validate:"required"`
}

func (h *Handler) MockComplete(c *gin.Context) {
	var req mockCompleteRequest
	if !bindAndValidate(c, &req) {
		return
	}

	paymentID, signature, err := h.service.MockCompletePayment(c.Request.Context(), req.OrderID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"razorpay_payment_id": paymentID, "razorpay_signature": signature})
}

func (h *Handler) History(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.ListHistory(c.Request.Context(), userID)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func bindAndValidate(c *gin.Context, req interface{}) bool {
	if err := c.ShouldBindJSON(req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return false
	}
	if fieldErrors := validator.Struct(req); fieldErrors != nil {
		response.Fail(c, http.StatusBadRequest, "validation_error", "one or more fields are invalid", fieldErrors)
		return false
	}
	return true
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrPlanNotFound):
		response.Fail(c, http.StatusNotFound, "plan_not_found", err.Error(), nil)
	case errors.Is(err, ErrCannotCheckoutFree):
		response.Fail(c, http.StatusBadRequest, "invalid_plan", err.Error(), nil)
	case errors.Is(err, ErrNotAnUpgrade):
		response.Fail(c, http.StatusBadRequest, "not_an_upgrade", err.Error(), nil)
	case errors.Is(err, ErrInvalidSignature):
		response.Fail(c, http.StatusBadRequest, "invalid_signature", err.Error(), nil)
	case errors.Is(err, ErrAlreadyProcessed):
		response.Fail(c, http.StatusConflict, "already_processed", err.Error(), nil)
	case errors.Is(err, ErrPaymentNotCaptured):
		response.Fail(c, http.StatusBadRequest, "payment_not_captured", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	case errors.Is(err, coupons.ErrNotFound):
		response.Fail(c, http.StatusNotFound, "coupon_not_found", err.Error(), nil)
	case errors.Is(err, coupons.ErrInactive):
		response.Fail(c, http.StatusBadRequest, "coupon_inactive", err.Error(), nil)
	case errors.Is(err, coupons.ErrExpired):
		response.Fail(c, http.StatusBadRequest, "coupon_expired", err.Error(), nil)
	case errors.Is(err, coupons.ErrExhausted):
		response.Fail(c, http.StatusBadRequest, "coupon_exhausted", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
