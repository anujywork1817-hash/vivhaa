package favourites

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

func (h *Handler) Add(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.Add(c.Request.Context(), userID, c.Param("profileId"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) Remove(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.service.Remove(c.Request.Context(), userID, c.Param("profileId")); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "removed from favourites"})
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
	case errors.Is(err, ErrSelfFavourite):
		response.Fail(c, http.StatusBadRequest, "self_favourite", err.Error(), nil)
	case errors.Is(err, ErrBlocked):
		response.Fail(c, http.StatusForbidden, "blocked", err.Error(), nil)
	case errors.Is(err, ErrAlreadyExists):
		response.Fail(c, http.StatusConflict, "already_exists", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
