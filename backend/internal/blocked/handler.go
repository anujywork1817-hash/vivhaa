package blocked

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

func (h *Handler) Block(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.Block(c.Request.Context(), userID, c.Param("profileId"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) Unblock(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.service.Unblock(c.Request.Context(), userID, c.Param("profileId")); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "unblocked"})
}

func (h *Handler) Status(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.Status(c.Request.Context(), userID, c.Param("profileId"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) List(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.List(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrSelfBlock):
		response.Fail(c, http.StatusBadRequest, "self_block", err.Error(), nil)
	case errors.Is(err, ErrAlreadyExists):
		response.Fail(c, http.StatusConflict, "already_exists", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
