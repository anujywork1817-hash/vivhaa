// Package response provides a standard JSON envelope for all API responses.
package response

import "github.com/gin-gonic/gin"

// Envelope is the standard shape every API response is wrapped in.
type Envelope struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   *Error      `json:"error,omitempty"`
	Meta    interface{} `json:"meta,omitempty"`
}

// Error describes a failed request in a machine-readable way.
type Error struct {
	Code    string      `json:"code"`
	Message string      `json:"message"`
	Details interface{} `json:"details,omitempty"`
}

// Success writes a 2xx success envelope.
func Success(c *gin.Context, status int, data interface{}, meta interface{}) {
	c.JSON(status, Envelope{
		Success: true,
		Data:    data,
		Meta:    meta,
	})
}

// OK writes a 200 success envelope with no meta.
func OK(c *gin.Context, data interface{}) {
	Success(c, 200, data, nil)
}

// Fail writes an error envelope with the given HTTP status.
func Fail(c *gin.Context, status int, code, message string, details interface{}) {
	c.JSON(status, Envelope{
		Success: false,
		Error: &Error{
			Code:    code,
			Message: message,
			Details: details,
		},
	})
}
