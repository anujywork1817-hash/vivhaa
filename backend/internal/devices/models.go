// Package devices tracks the push-notification tokens registered by each
// user's devices. Notifications are addressed to a user, but push delivery
// is per-device, so this is the lookup that bridges the two.
package devices

import "time"

type DeviceToken struct {
	ID        string
	UserID    string
	Token     string
	Platform  string
	CreatedAt time.Time
	UpdatedAt time.Time
}
