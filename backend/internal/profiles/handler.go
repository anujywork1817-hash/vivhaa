package profiles

import (
	"errors"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
	"matrimony-backend/pkg/validator"
)

const maxUploadBytes = 6 * 1024 * 1024 // slightly above MaxPhotoSizeBytes to allow multipart overhead

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) Create(c *gin.Context) {
	var req ProfileInput
	if !bindAndValidate(c, &req) {
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.Create(c.Request.Context(), userID, req)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) GetMe(c *gin.Context) {
	userID := c.GetString("user_id")
	resp, err := h.service.GetMine(c.Request.Context(), userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) UpdateMe(c *gin.Context) {
	var req ProfileInput
	if !bindAndValidate(c, &req) {
		return
	}

	userID := c.GetString("user_id")
	resp, err := h.service.Update(c.Request.Context(), userID, req)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

type updateLocationRequest struct {
	Latitude  float64 `json:"latitude" validate:"required"`
	Longitude float64 `json:"longitude" validate:"required"`
}

func (h *Handler) UpdateLocation(c *gin.Context) {
	var req updateLocationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return
	}

	userID := c.GetString("user_id")
	if err := h.service.UpdateLocation(c.Request.Context(), userID, req.Latitude, req.Longitude); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "location updated"})
}

func (h *Handler) GetByID(c *gin.Context) {
	profileID := c.Param("id")
	userID := c.GetString("user_id")

	resp, err := h.service.GetByID(c.Request.Context(), profileID, userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) GetByCode(c *gin.Context) {
	code := c.Param("code")
	userID := c.GetString("user_id")

	resp, err := h.service.GetByCode(c.Request.Context(), code, userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) GetContactInfo(c *gin.Context) {
	profileID := c.Param("id")
	userID := c.GetString("user_id")

	resp, err := h.service.GetContactInfo(c.Request.Context(), profileID, userID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) UploadPhoto(c *gin.Context) {
	fileHeader, err := c.FormFile("photo")
	if err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "form field 'photo' is required", nil)
		return
	}
	if fileHeader.Size > maxUploadBytes {
		response.Fail(c, http.StatusBadRequest, "file_too_large", "photo exceeds the maximum allowed size", nil)
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

	resp, err := h.service.UploadPhoto(c.Request.Context(), userID, data, contentType)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) SetPrimaryPhoto(c *gin.Context) {
	photoID := c.Param("photoId")
	userID := c.GetString("user_id")

	resp, err := h.service.SetPrimaryPhoto(c.Request.Context(), userID, photoID)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) DeletePhoto(c *gin.Context) {
	photoID := c.Param("photoId")
	userID := c.GetString("user_id")

	if err := h.service.DeletePhoto(c.Request.Context(), userID, photoID); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "photo deleted"})
}

func bindAndValidate(c *gin.Context, req interface{}) bool {
	if err := c.ShouldBindJSON(req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return false
	}
	if fieldErrors := validator.Struct(req); fieldErrors != nil {
		response.Fail(c, http.StatusBadRequest, "validation_error", "one or more fields are invalid", fieldErrors)
		return false
	}
	return true
}

func writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrAlreadyExists):
		response.Fail(c, http.StatusConflict, "already_exists", err.Error(), nil)
	case errors.Is(err, ErrForbidden):
		response.Fail(c, http.StatusForbidden, "forbidden", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	case errors.Is(err, ErrTooManyPhotos):
		response.Fail(c, http.StatusBadRequest, "too_many_photos", err.Error(), nil)
	case errors.Is(err, ErrInvalidImage):
		response.Fail(c, http.StatusBadRequest, "invalid_image", err.Error(), nil)
	case errors.Is(err, ErrPhotoNotOwned):
		response.Fail(c, http.StatusForbidden, "forbidden", err.Error(), nil)
	case errors.Is(err, ErrPremiumRequired):
		response.Fail(c, http.StatusPaymentRequired, "premium_required", err.Error(), nil)
	case errors.Is(err, ErrInvalidLocation):
		response.Fail(c, http.StatusBadRequest, "invalid_location", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
