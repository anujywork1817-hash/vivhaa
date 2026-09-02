package middleware

import (
	"context"
	"net/http"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
)

// UnlockChecker is the one lookup RequireUnlocked needs
// (users.Repository.IsUnlocked) — declared here rather than importing
// internal/users directly, the same pattern profiles.BlockChecker uses to
// avoid an import cycle risk between middleware and the rest of the app.
// *users.Repository satisfies this interface structurally.
type UnlockChecker interface {
	IsUnlocked(ctx context.Context, userID string) (bool, error)
}

// RequireUnlocked gates every real (non-demo) feature behind the one-time
// ₹1 unlock payment (see internal/unlock) — separate from, and layered in
// front of, the existing subscription/premium tier system, which keeps
// working exactly as before once a user is unlocked. Must run after
// RequireAuth (needs "user_id" already set in context).
//
// Responds 402 Payment Required with error code "unlock_required" so the
// Flutter client's api_error_mapper can route the user straight back to
// the paywall screen, including mid-navigation on an already-onboarded
// but unpaid account (e.g. after a reinstall).
func RequireUnlocked(checker UnlockChecker) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.GetString("user_id")
		unlocked, err := checker.IsUnlocked(c.Request.Context(), userID)
		if err != nil {
			response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
			c.Abort()
			return
		}
		if !unlocked {
			response.Fail(c, http.StatusPaymentRequired, "unlock_required", "pay the one-time unlock fee to access this feature", nil)
			c.Abort()
			return
		}
		c.Next()
	}
}
