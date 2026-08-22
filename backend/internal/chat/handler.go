package chat

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

type sendMessageRequest struct {
	Body      string  `json:"body" validate:"required,min=1,max=4000"`
	ReplyToID *string `json:"reply_to_message_id"`
}

func (h *Handler) SendMessage(c *gin.Context) {
	var req sendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.SendMessage(c.Request.Context(), userID, c.Param("userId"), req.Body, req.ReplyToID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) GetHistory(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.GetHistory(c.Request.Context(), userID, c.Param("userId"))
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) ListConversations(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.ListConversations(c.Request.Context(), userID)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) RequestContact(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.RequestContact(c.Request.Context(), userID, c.Param("userId"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) AcceptContact(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.RespondContact(c.Request.Context(), userID, c.Param("messageId"), true)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) DeclineContact(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.RespondContact(c.Request.Context(), userID, c.Param("messageId"), false)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrSelfMessage):
		response.Fail(c, http.StatusBadRequest, "self_message", err.Error(), nil)
	case errors.Is(err, ErrChatNotAllowed):
		response.Fail(c, http.StatusForbidden, "chat_not_allowed", err.Error(), nil)
	case errors.Is(err, ErrPremiumRequired):
		response.Fail(c, http.StatusPaymentRequired, "premium_required", err.Error(), nil)
	case errors.Is(err, ErrBlocked):
		response.Fail(c, http.StatusForbidden, "blocked", err.Error(), nil)
	case errors.Is(err, ErrContactRequestPending):
		response.Fail(c, http.StatusConflict, "contact_request_pending", err.Error(), nil)
	case errors.Is(err, ErrContactRequestNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	case errors.Is(err, ErrNotContactRecipient):
		response.Fail(c, http.StatusForbidden, "forbidden", err.Error(), nil)
	case errors.Is(err, ErrContactRequestResolved):
		response.Fail(c, http.StatusConflict, "already_resolved", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
