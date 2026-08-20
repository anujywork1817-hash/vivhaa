package reference

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /reference/* endpoints on the given router group.
//
// These sit behind auth like every other module. The onboarding flow that
// consumes them runs after sign-up, so a token is always in hand by then.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	ref := rg.Group("/reference")
	ref.Use(middleware.RequireAuth(issuer), cacheForADay())

	ref.GET("/countries", h.ListCountries)
	ref.GET("/countries/:country/states", h.ListStates)
	ref.GET("/countries/:country/states/:state/cities", h.ListCities)
	ref.GET("/religions", h.ListReligions)
}

// cacheForADay lets clients and any CDN in front of the API hold these
// lists. The data only changes on deploy, so a stale day is harmless and it
// keeps the pickers off the network on every onboarding step.
func cacheForADay() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Cache-Control", "public, max-age=86400")
		c.Next()
	}
}
