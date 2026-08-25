package preferences

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

func (h *Handler) Upsert(c *gin.Context) {
	var req UpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}
	if fieldErrors := validator.Struct(&req); fieldErrors != nil {
		response.Fail(c, http.StatusBadRequest, "validation_error", "one or more fields are invalid", fieldErrors)
		return
	}
	if err := req.Validate(); err != nil {
		response.Fail(c, http.StatusBadRequest, "validation_error", err.Error(), nil)
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.Upsert(c.Request.Context(), userID, req)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) GetMine(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.GetMine(c.Request.Context(), userID)
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "preferences not set yet", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}
