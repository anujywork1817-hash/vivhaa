// Package logger provides a structured, leveled logger built on slog.
package logger

import (
	"log/slog"
	"os"
)

// New returns a JSON structured logger. In dev mode it logs at debug level
// with human-readable text output; otherwise JSON at info level.
func New(env string) *slog.Logger {
	var handler slog.Handler
	opts := &slog.HandlerOptions{Level: slog.LevelInfo}

	if env == "dev" {
		opts.Level = slog.LevelDebug
		handler = slog.NewTextHandler(os.Stdout, opts)
	} else {
		handler = slog.NewJSONHandler(os.Stdout, opts)
	}

	logger := slog.New(handler)
	slog.SetDefault(logger)
	return logger
}
