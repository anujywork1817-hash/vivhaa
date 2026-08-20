package moderation

import (
	"net/http"
	"strconv"

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

func (h *Handler) ListPending(c *gin.Context) {
	page, _ := strconv.Atoi(c.Query("page"))
	limit, _ := strconv.Atoi(c.Query("limit"))

	resp, meta, err := h.service.ListPending(c.Request.Context(), page, limit)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.Success(c, http.StatusOK, resp, meta)
}

func (h *Handler) Resolve(c *gin.Context) {
	var req ResolveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}
	if fieldErrors := validator.Struct(&req); fieldErrors != nil {
		response.Fail(c, http.StatusBadRequest, "validation_error", "one or more fields are invalid", fieldErrors)
		return
	}

	reviewerID := c.GetString("user_id")
	resp, err := h.service.Resolve(c.Request.Context(), c.Param("id"), reviewerID, req)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}
