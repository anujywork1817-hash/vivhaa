package queue

const (
	TopicProfileUpdated       = "profile.updated"
	TopicNotificationDispatch = "notification.dispatch"
)

// ProfileUpdatedEvent tells cmd/worker to (re)index a profile in
// Elasticsearch. Only the ID is needed — the worker reads the current
// row from Postgres rather than trusting a possibly-stale event payload.
type ProfileUpdatedEvent struct {
	ProfileID string `json:"profile_id"`
	UserID    string `json:"user_id"`
}

// NotificationDispatchEvent tells cmd/notification to persist an in-app
// notification and attempt external delivery (push/email/sms).
//
// When PushOnly is set, cmd/notification skips persisting an in-app
// notification entirely and sends PushData as a data-only FCM message
// instead of the usual title/body one — for transient signaling that
// shouldn't appear in the Notifications list.
type NotificationDispatchEvent struct {
	UserID string         `json:"user_id"`
	Type   string         `json:"type"`
	Title  string         `json:"title"`
	Body   string         `json:"body"`
	Data   map[string]any `json:"data,omitempty"`

	PushOnly bool              `json:"push_only,omitempty"`
	PushData map[string]string `json:"push_data,omitempty"`
}
