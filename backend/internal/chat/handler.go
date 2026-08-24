package chat

import (
	"errors"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/storage"
	"matrimony-backend/pkg/response"
)

type Handler struct {
	service  *Service
	uploader *storage.PhotoUploader
}

func NewHandler(service *Service, uploader *storage.PhotoUploader) *Handler {
	return &Handler{service: service, uploader: uploader}
}

type sendMessageRequest struct {
	Body      string  `json:"body" validate:"required,min=1,max=4000"`
	ReplyToID *string `json:"reply_to_message_id"`
}

func (h *Handler) SendMessage(c *gin.Context) {
	var req sendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.SendMessage(c.Request.Context(), userID, c.Param("userId"), req.Body, req.ReplyToID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

// UploadAttachment sends an image or document as a chat message: uploads
// the file (reusing the same public-photos-bucket path profile photos
// use), then creates the message with the resulting URL. multipart form
// fields: "file" (required), "caption" (optional, shown as the message
// body/notification text).
func (h *Handler) UploadAttachment(c *gin.Context) {
	fileHeader, err := c.FormFile("file")
	if err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "form field 'file' is required", nil)
		return
	}

	isImage, err := storage.ValidateChatAttachment(fileHeader.Size, fileHeader.Header.Get("Content-Type"))
	if err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_file", err.Error(), nil)
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

	userID := c.GetString("user_id")
	_, url, err := h.uploader.UploadChatAttachment(c.Request.Context(), userID, data, fileHeader.Header.Get("Content-Type"))
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "upload_failed", "could not upload the file", nil)
		return
	}

	kind := MessageKindDocument
	caption := c.PostForm("caption")
	if isImage {
		kind = MessageKindImage
		if caption == "" {
			caption = "Photo"
		}
	} else if caption == "" {
		caption = fileHeader.Filename
	}

	resp, err := h.service.SendAttachment(c.Request.Context(), userID, c.Param("userId"), kind, caption, url)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) GetHistory(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.GetHistory(c.Request.Context(), userID, c.Param("userId"))
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) ListConversations(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.ListConversations(c.Request.Context(), userID)
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) RequestContact(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.RequestContact(c.Request.Context(), userID, c.Param("userId"))
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) AcceptContact(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.RespondContact(c.Request.Context(), userID, c.Param("messageId"), true)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) DeclineContact(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.RespondContact(c.Request.Context(), userID, c.Param("messageId"), false)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrSelfMessage):
		response.Fail(c, http.StatusBadRequest, "self_message", err.Error(), nil)
	case errors.Is(err, ErrChatNotAllowed):
		response.Fail(c, http.StatusForbidden, "chat_not_allowed", err.Error(), nil)
	case errors.Is(err, ErrPremiumRequired):
		response.Fail(c, http.StatusPaymentRequired, "premium_required", err.Error(), nil)
	case errors.Is(err, ErrBlocked):
		response.Fail(c, http.StatusForbidden, "blocked", err.Error(), nil)
	case errors.Is(err, ErrContactRequestPending):
		response.Fail(c, http.StatusConflict, "contact_request_pending", err.Error(), nil)
	case errors.Is(err, ErrContactRequestNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	case errors.Is(err, ErrNotContactRecipient):
		response.Fail(c, http.StatusForbidden, "forbidden", err.Error(), nil)
	case errors.Is(err, ErrContactRequestResolved):
		response.Fail(c, http.StatusConflict, "already_resolved", err.Error(), nil)
	case errors.Is(err, ErrContactInfoBlocked):
		response.Fail(c, http.StatusUnprocessableEntity, "message_blocked", userFacingBlockMessage, nil)
	case errors.Is(err, ErrChatRestricted):
		response.Fail(c, http.StatusTooManyRequests, "chat_restricted", "You're temporarily unable to send messages. Please try again later.", nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
