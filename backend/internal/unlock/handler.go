package unlock

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
	"matrimony-backend/pkg/validator"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) Status(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.Status(c.Request.Context(), userID)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Checkout(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.Checkout(c.Request.Context(), userID)
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

// mockCompleteRequest/MockComplete: dev-only, see routes.go — only
// registered when the mock gateway is active, mirroring
// payments.Handler.MockComplete exactly.
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
	case errors.Is(err, ErrInvalidSignature):
		response.Fail(c, http.StatusBadRequest, "invalid_signature", err.Error(), nil)
	case errors.Is(err, ErrAlreadyProcessed):
		response.Fail(c, http.StatusConflict, "already_processed", err.Error(), nil)
	case errors.Is(err, ErrPaymentNotCaptured):
		response.Fail(c, http.StatusBadRequest, "payment_not_captured", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
