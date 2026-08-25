package verification

import (
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
)

const maxUploadBytes = 11 * 1024 * 1024

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) Submit(c *gin.Context) {
	documentType := c.PostForm("document_type")

	fileHeader, err := c.FormFile("document")
	if err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "form field 'document' is required", nil)
		return
	}
	if fileHeader.Size > maxUploadBytes {
		response.Fail(c, http.StatusBadRequest, "file_too_large", "document exceeds the maximum allowed size", nil)
		return
	}

	file, err := fileHeader.Open()
	if err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "could not read uploaded file", nil)
		return
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "could not read uploaded file", nil)
		return
	}

	contentType := fileHeader.Header.Get("Content-Type")
	userID := c.GetString("user_id")

	resp, err := h.service.Submit(c.Request.Context(), userID, documentType, data, contentType)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) GetMine(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.GetMine(c.Request.Context(), userID)
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "no verification submitted yet", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) ListMine(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.ListByUserID(c.Request.Context(), userID)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

// ListForUser is the admin-only counterpart of ListMine — it looks up an
// arbitrary user's documents by :userId rather than the caller's own.
func (h *Handler) ListForUser(c *gin.Context) {
	resp, err := h.service.ListByUserID(c.Request.Context(), c.Param("userId"))
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
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

func (h *Handler) Approve(c *gin.Context) {
	var req ReviewRequest
	_ = c.ShouldBindJSON(&req)

	reviewerID := c.GetString("user_id")
	resp, err := h.service.Approve(c.Request.Context(), c.Param("id"), reviewerID, req.Notes)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) Reject(c *gin.Context) {
	var req ReviewRequest
	_ = c.ShouldBindJSON(&req)

	reviewerID := c.GetString("user_id")
	resp, err := h.service.Reject(c.Request.Context(), c.Param("id"), reviewerID, req.Notes)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrInvalidDocumentType):
		response.Fail(c, http.StatusBadRequest, "invalid_document_type", err.Error(), nil)
	case errors.Is(err, ErrInvalidFile):
		response.Fail(c, http.StatusBadRequest, "invalid_file", err.Error(), nil)
	case errors.Is(err, ErrAlreadyPending):
		response.Fail(c, http.StatusConflict, "already_pending", err.Error(), nil)
	case errors.Is(err, ErrAlreadyApproved):
		response.Fail(c, http.StatusConflict, "already_approved", err.Error(), nil)
	case errors.Is(err, ErrAlreadyReviewed):
		response.Fail(c, http.StatusConflict, "already_reviewed", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
