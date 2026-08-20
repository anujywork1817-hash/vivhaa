package interests

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

func (h *Handler) Express(c *gin.Context) {
	userID := c.GetString("user_id")
	profileID := c.Param("profileId")

	resp, err := h.service.Express(c.Request.Context(), userID, profileID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) Accept(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.Accept(c.Request.Context(), userID, c.Param("id"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Decline(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.Decline(c.Request.Context(), userID, c.Param("id"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) ListDeleted(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.ListDeleted(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Delete(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.service.Delete(c.Request.Context(), userID, c.Param("id")); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "deleted"})
}

func (h *Handler) Remind(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.service.Remind(c.Request.Context(), userID, c.Param("id")); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "reminder sent"})
}

func (h *Handler) ListSent(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.ListSent(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) ListReceived(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.ListReceived(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrSelfInterest):
		response.Fail(c, http.StatusBadRequest, "self_interest", err.Error(), nil)
	case errors.Is(err, ErrAlreadyExists):
		response.Fail(c, http.StatusConflict, "already_exists", err.Error(), nil)
	case errors.Is(err, ErrForbidden):
		response.Fail(c, http.StatusForbidden, "forbidden", err.Error(), nil)
	case errors.Is(err, ErrAlreadyResponded):
		response.Fail(c, http.StatusConflict, "already_responded", err.Error(), nil)
	case errors.Is(err, ErrBlocked):
		response.Fail(c, http.StatusForbidden, "blocked", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
