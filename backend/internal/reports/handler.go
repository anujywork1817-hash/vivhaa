package reports

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

func (h *Handler) Submit(c *gin.Context) {
	var req ReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}
	if fieldErrors := validator.Struct(&req); fieldErrors != nil {
		response.Fail(c, http.StatusBadRequest, "validation_error", "one or more fields are invalid", fieldErrors)
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.Submit(c.Request.Context(), userID, c.Param("profileId"), req)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrSelfReport):
		response.Fail(c, http.StatusBadRequest, "self_report", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
