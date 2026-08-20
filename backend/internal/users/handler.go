package users

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
)

type Handler struct {
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// Me returns the authenticated user's own record. Proves the JWT auth
// guard is wired correctly end to end.
func (h *Handler) Me(c *gin.Context) {
	userID := c.GetString("user_id")

	user, err := h.repo.GetByID(c.Request.Context(), userID)
	if errors.Is(err, ErrNotFound) {
		response.Fail(c, http.StatusNotFound, "not_found", "user not found", nil)
		return
	}
	if err != nil {
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
		return
	}

	response.OK(c, user)
}
