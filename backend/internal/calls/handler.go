package calls

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) ICEServers(c *gin.Context) {
	userID := c.GetString("user_id")
	response.OK(c, h.service.ICEServers(userID))
}

// AdminListCallHistory backs GET /admin/call-history. from/to are plain
// YYYY-MM-DD dates (not full timestamps) — the admin UI's date-range
// picker works in whole days; `to` is treated as end-of-day so a range
// like from=2026-01-01&to=2026-01-01 includes all of that one day.
func (h *Handler) AdminListCallHistory(c *gin.Context) {
	var f ListFilter
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	if v := c.Query("from"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			f.FromDate = &t
		}
	}
	if v := c.Query("to"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			endOfDay := t.Add(24*time.Hour - time.Second)
			f.ToDate = &endOfDay
		}
	}
	f.Page, _ = strconv.Atoi(c.Query("page"))
	f.Limit, _ = strconv.Atoi(c.Query("limit"))

	rows, meta, err := h.service.AdminListCallHistory(c.Request.Context(), f)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.Success(c, http.StatusOK, rows, meta)
}
