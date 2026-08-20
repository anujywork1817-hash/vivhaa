package devices

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

type registerRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

func (h *Handler) Register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}

	userID := c.GetString("user_id")
	if err := h.service.Register(c.Request.Context(), userID, req.Token, req.Platform); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "registered"})
}

func (h *Handler) Unregister(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}

	userID := c.GetString("user_id")
	if err := h.service.Unregister(c.Request.Context(), userID, req.Token); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "unregistered"})
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrTokenRequired):
		response.Fail(c, http.StatusBadRequest, "token_required", err.Error(), nil)
	case errors.Is(err, ErrInvalidPlatform):
		response.Fail(c, http.StatusBadRequest, "invalid_platform", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
