package admin

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

func (h *Handler) ListUsers(c *gin.Context) {
	var f ListUsersFilter
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	if v := c.Query("role"); v != "" {
		f.Role = &v
	}
	if v := c.Query("search"); v != "" {
		f.Search = &v
	}
	f.Page, _ = strconv.Atoi(c.Query("page"))
	f.Limit, _ = strconv.Atoi(c.Query("limit"))

	users, meta, err := h.service.ListUsers(c.Request.Context(), f)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.Success(c, http.StatusOK, users, meta)
}

func (h *Handler) GetUser(c *gin.Context) {
	resp, err := h.service.GetUser(c.Request.Context(), c.Param("id"))
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "user not found", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Suspend(c *gin.Context) {
	resp, err := h.service.Suspend(c.Request.Context(), c.Param("id"))
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "user not found", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Activate(c *gin.Context) {
	resp, err := h.service.Activate(c.Request.Context(), c.Param("id"))
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "user not found", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Dashboard(c *gin.Context) {
	resp, err := h.service.GetDashboard(c.Request.Context())
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) ListSubscriptions(c *gin.Context) {
	var f ListSubscriptionsFilter
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	f.Page, _ = strconv.Atoi(c.Query("page"))
	f.Limit, _ = strconv.Atoi(c.Query("limit"))

	rows, meta, err := h.service.ListSubscriptions(c.Request.Context(), f)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.Success(c, http.StatusOK, rows, meta)
}

func (h *Handler) Revenue(c *gin.Context) {
	resp, err := h.service.GetRevenue(c.Request.Context())
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}
