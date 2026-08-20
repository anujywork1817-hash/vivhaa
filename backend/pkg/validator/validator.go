// Package validator wraps go-playground/validator with helpers to turn
// validation failures into human-readable field error lists.
package validator

import (
	"fmt"
	"strings"

	"github.com/go-playground/validator/v10"
)

var v = validator.New()

// FieldError is a single validation failure on one struct field.
type FieldError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

// Struct validates s using struct tags and returns a flat list of
// field-level errors, or nil if s is valid.
func Struct(s interface{}) []FieldError {
	err := v.Struct(s)
	if err == nil {
		return nil
	}

	validationErrors, ok := err.(validator.ValidationErrors)
	if !ok {
		return []FieldError{{Field: "", Message: err.Error()}}
	}

	fieldErrors := make([]FieldError, 0, len(validationErrors))
	for _, fe := range validationErrors {
		fieldErrors = append(fieldErrors, FieldError{
			Field:   strings.ToLower(fe.Field()),
			Message: friendlyMessage(fe),
		})
	}
	return fieldErrors
}

func friendlyMessage(fe validator.FieldError) string {
	field := strings.ToLower(fe.Field())
	switch fe.Tag() {
	case "required":
		return fmt.Sprintf("%s is required", field)
	case "email":
		return fmt.Sprintf("%s must be a valid email", field)
	case "min":
		return fmt.Sprintf("%s must be at least %s characters", field, fe.Param())
	case "max":
		return fmt.Sprintf("%s must be at most %s characters", field, fe.Param())
	case "e164":
		return fmt.Sprintf("%s must be a valid phone number (E.164 format)", field)
	default:
		return fmt.Sprintf("%s failed validation: %s", field, fe.Tag())
	}
}
