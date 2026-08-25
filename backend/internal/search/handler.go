package search

import (
	"log/slog"
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

func (h *Handler) Search(c *gin.Context) {
	var q Query
	if err := c.ShouldBindQuery(&q); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_query", "one or more query parameters are invalid", err.Error())
		return
	}

	userID := c.GetString("user_id")
	results, meta, err := h.service.Search(c.Request.Context(), userID, q)
	if err != nil {
		slog.Error("search failed", "error", err, "query", q)
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}

	response.Success(c, http.StatusOK, results, meta)
}
