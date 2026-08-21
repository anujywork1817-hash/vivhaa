package middleware

import (
	"log/slog"
	"time"

	"github.com/gin-gonic/gin"
)

// RequestLog logs one line per HTTP request through the app's slog logger.
//
// The API previously ran gin.New() with no logger at all, which meant a
// request that was rejected — a 401, a 404, a client that never sent the
// header it should have — left no trace whatsoever. Debugging "the app says
// it can't load X" then came down to guesswork, because the logs could not
// even answer whether the request arrived.
//
// Deliberately not gin.Logger(): that writes unstructured text to stdout,
// while everything else here is structured slog.
func RequestLog(log *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		query := c.Request.URL.RawQuery

		c.Next()

		status := c.Writer.Status()
		attrs := []any{
			"method", c.Request.Method,
			"path", path,
			"status", status,
			"duration_ms", time.Since(start).Milliseconds(),
			"ip", c.ClientIP(),
		}
		if query != "" {
			attrs = append(attrs, "query", query)
		}
		// Whether an Authorization header was present at all — not its value.
		// A picker failing because the client never sent a token looks exactly
		// like one failing because the token was rejected, and this is the
		// cheapest way to tell those apart without ever logging a credential.
		if c.GetHeader("Authorization") != "" {
			attrs = append(attrs, "authed", true)
		}
		if errs := c.Errors.ByType(gin.ErrorTypePrivate).String(); errs != "" {
			attrs = append(attrs, "errors", errs)
		}

		switch {
		case status >= 500:
			log.Error("request", attrs...)
		case status >= 400:
			log.Warn("request", attrs...)
		default:
			log.Info("request", attrs...)
		}
	}
}
