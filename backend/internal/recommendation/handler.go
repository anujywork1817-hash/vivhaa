package recommendation

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) Recommended(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.GetRecommended(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Daily(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.GetDaily(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) All(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.GetAll(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Nearby(c *gin.Context) {
	userID := c.GetString("user_id")

	radiusKM := 0.0
	if raw := c.Query("radius_km"); raw != "" {
		parsed, err := strconv.ParseFloat(raw, 64)
		if err != nil {
			response.Fail(c, http.StatusBadRequest, "invalid_query", "radius_km must be a number", nil)
			return
		}
		radiusKM = parsed
	}

	resp, err := h.service.GetNearby(c.Request.Context(), userID, radiusKM)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrProfileRequired):
		response.Fail(c, http.StatusBadRequest, "profile_required", err.Error(), nil)
	case errors.Is(err, ErrLocationRequired):
		response.Fail(c, http.StatusBadRequest, "location_required", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
