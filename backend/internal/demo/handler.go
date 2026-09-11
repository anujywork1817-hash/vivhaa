package demo

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

func (h *Handler) SwipeDeck(c *gin.Context) {
	userID := c.GetString("user_id")
	var requestedGender *string
	if v := c.Query("gender"); v != "" {
		requestedGender = &v
	}
	resp, err := h.service.SwipeDeck(c.Request.Context(), userID, requestedGender)
	if errors.Is(err, ErrProfileRequired) {
		response.Fail(c, http.StatusBadRequest, "profile_required", err.Error(), nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}
