package ai

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

func (h *Handler) Chat(c *gin.Context) {
	var req ChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}
	if fieldErrors := validator.Struct(&req); fieldErrors != nil {
		response.Fail(c, http.StatusBadRequest, "validation_error", "one or more fields are invalid", fieldErrors)
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.Chat(c.Request.Context(), userID, req.Message)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) History(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.History(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Icebreakers(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.Icebreakers(c.Request.Context(), userID, c.Param("profileId"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) MatchBlurb(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.MatchBlurb(c.Request.Context(), userID, c.Param("profileId"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrNotConfigured):
		response.Fail(c, http.StatusServiceUnavailable, "ai_not_configured", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
