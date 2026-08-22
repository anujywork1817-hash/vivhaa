package notifications

import (
	"context"
	"encoding/json"
	"time"
)

const defaultLimit = 20
const maxLimit = 100

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// Create persists a notification for userID. data is marshaled to JSON;
// pass nil if there's no structured payload.
func (s *Service) Create(ctx context.Context, userID, notifType, title string, body *string, data any) (Notification, error) {
	var raw []byte
	if data != nil {
		encoded, err := json.Marshal(data)
		if err != nil {
			return Notification{}, err
		}
		raw = encoded
	}
	return s.repo.Create(ctx, userID, notifType, title, body, raw)
}

func (s *Service) List(ctx context.Context, userID string, page, limit int) (ListResponse, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = defaultLimit
	}
	// BUG-L01: no upper bound meant a client (or a probe) could ask for
	// limit=1000000 and force a full-table-ish scan and a huge response.
	if limit > maxLimit {
		limit = maxLimit
	}

	rows, err := s.repo.List(ctx, userID, limit, (page-1)*limit)
	if err != nil {
		return ListResponse{}, err
	}

	unread, err := s.repo.CountUnread(ctx, userID)
	if err != nil {
		return ListResponse{}, err
	}

	out := make([]Response, 0, len(rows))
	for _, n := range rows {
		out = append(out, toResponse(n))
	}
	return ListResponse{Notifications: out, UnreadCount: unread}, nil
}

func (s *Service) MarkRead(ctx context.Context, userID, id string) error {
	return s.repo.MarkRead(ctx, userID, id)
}

func (s *Service) MarkAllRead(ctx context.Context, userID string) error {
	return s.repo.MarkAllRead(ctx, userID)
}

// ToResponse builds the same wire shape GET /notifications returns for one
// row — exported so cmd/notification can push a freshly created
// notification live over the websocket in the exact shape the client
// already knows how to render, without a second round trip back through
// the REST endpoint.
func ToResponse(n Notification) Response {
	return toResponse(n)
}

func toResponse(n Notification) Response {
	var data any
	if len(n.Data) > 0 {
		_ = json.Unmarshal(n.Data, &data)
	}
	return Response{
		ID:        n.ID,
		Type:      n.Type,
		Title:     n.Title,
		Body:      n.Body,
		Data:      data,
		Read:      n.ReadAt != nil,
		CreatedAt: n.CreatedAt.Format(time.RFC3339),
	}
}
