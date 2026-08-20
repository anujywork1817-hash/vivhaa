package notifications

import (
	"context"
	"encoding/json"
	"time"
)

const defaultLimit = 20

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// Create persists a notification for userID. data is marshaled to JSON;
// pass nil if there's no structured payload.
func (s *Service) Create(ctx context.Context, userID, notifType, title string, body *string, data any) error {
	var raw []byte
	if data != nil {
		encoded, err := json.Marshal(data)
		if err != nil {
			return err
		}
		raw = encoded
	}
	_, err := s.repo.Create(ctx, userID, notifType, title, body, raw)
	return err
}

func (s *Service) List(ctx context.Context, userID string, page, limit int) (ListResponse, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = defaultLimit
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
