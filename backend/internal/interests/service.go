package interests

import (
	"context"
	"errors"
	"time"

	"matrimony-backend/internal/analytics"
	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/queue"
)

var (
	ErrSelfInterest     = errors.New("cannot express interest in your own profile")
	ErrForbidden        = errors.New("you are not the recipient of this interest")
	ErrAlreadyResponded = errors.New("interest has already been responded to")
	ErrBlocked          = errors.New("you can't interact with this profile")
)

type Service struct {
	repo         *Repository
	profilesRepo *profiles.Repository
	blockedRepo  *blocked.Repository
	publisher    *queue.Publisher
	analyticsSvc *analytics.Service
}

func NewService(repo *Repository, profilesRepo *profiles.Repository, blockedRepo *blocked.Repository, publisher *queue.Publisher, analyticsSvc *analytics.Service) *Service {
	return &Service{repo: repo, profilesRepo: profilesRepo, blockedRepo: blockedRepo, publisher: publisher, analyticsSvc: analyticsSvc}
}

// Express creates an interest from senderUserID toward the owner of
// targetProfileID.
func (s *Service) Express(ctx context.Context, senderUserID, targetProfileID string) (Response, error) {
	targetProfile, err := s.profilesRepo.GetByID(ctx, targetProfileID)
	if errors.Is(err, profiles.ErrNotFound) {
		return Response{}, ErrNotFound
	}
	if err != nil {
		return Response{}, err
	}

	if targetProfile.UserID == senderUserID {
		return Response{}, ErrSelfInterest
	}

	isBlocked, err := s.blockedRepo.IsBlocked(ctx, senderUserID, targetProfile.UserID)
	if err != nil {
		return Response{}, err
	}
	if isBlocked {
		return Response{}, ErrBlocked
	}

	i, err := s.repo.Create(ctx, senderUserID, targetProfile.UserID)
	if err != nil {
		return Response{}, err
	}

	_ = s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
		UserID: targetProfile.UserID,
		Type:   "interest_received",
		Title:  "New interest received",
		Body:   "Someone has expressed interest in your profile.",
		Data:   map[string]any{"interest_id": i.ID},
	})

	return toResponse(i), nil
}

func (s *Service) Accept(ctx context.Context, userID, interestID string) (Response, error) {
	return s.respond(ctx, userID, interestID, "accepted")
}

func (s *Service) Decline(ctx context.Context, userID, interestID string) (Response, error) {
	return s.respond(ctx, userID, interestID, "declined")
}

func (s *Service) respond(ctx context.Context, userID, interestID, status string) (Response, error) {
	existing, err := s.repo.GetByID(ctx, interestID)
	if err != nil {
		return Response{}, err
	}

	if existing.ReceiverUserID != userID {
		return Response{}, ErrForbidden
	}
	if existing.Status != "pending" {
		return Response{}, ErrAlreadyResponded
	}

	updated, err := s.repo.UpdateStatus(ctx, interestID, status)
	if err != nil {
		return Response{}, err
	}

	if status == "accepted" {
		_ = s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
			UserID: updated.SenderUserID,
			Type:   "match",
			Title:  "It's a match!",
			Body:   "You have a new match! You can now start chatting.",
			Data:   map[string]any{"interest_id": updated.ID},
		})
		_ = s.analyticsSvc.Track(ctx, "match", &updated.SenderUserID, map[string]string{"interest_id": updated.ID, "receiver_user_id": updated.ReceiverUserID})
	}

	return toResponse(updated), nil
}

func (s *Service) ListSent(ctx context.Context, userID string) ([]Response, error) {
	rows, err := s.repo.ListSent(ctx, userID)
	if err != nil {
		return nil, err
	}
	return toResponseListWithProfile(rows), nil
}

func (s *Service) ListReceived(ctx context.Context, userID string) ([]Response, error) {
	rows, err := s.repo.ListReceived(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Opening the received list is the moment these count as seen, which
	// is what flips the sender's "Viewed / Not viewed yet" indicator.
	// Deliberately after the read, so this response still reports the
	// pre-view state and a failure here can't hide the list itself.
	if err := s.repo.MarkReceivedViewed(ctx, userID); err != nil {
		return nil, err
	}

	return toResponseListWithProfile(rows), nil
}

// ListDeleted returns the caller's soft-deleted interests, in either
// direction — Inbox > More > Deleted.
func (s *Service) ListDeleted(ctx context.Context, userID string) ([]Response, error) {
	rows, err := s.repo.ListDeleted(ctx, userID)
	if err != nil {
		return nil, err
	}
	return toResponseListWithProfile(rows), nil
}

// Delete removes an interest the caller is party to — used to withdraw a
// request you sent, or clear one you received.
func (s *Service) Delete(ctx context.Context, userID, interestID string) error {
	return s.repo.Delete(ctx, interestID, userID)
}

// Remind re-notifies the receiver about a request that's still pending.
// It doesn't create a second interest (the unique constraint forbids
// that) — it just re-sends the notification.
func (s *Service) Remind(ctx context.Context, userID, interestID string) error {
	interest, err := s.repo.GetByID(ctx, interestID)
	if err != nil {
		return err
	}
	if interest.SenderUserID != userID {
		return ErrNotFound
	}
	if interest.Status != "pending" {
		return ErrAlreadyResponded
	}

	sender, err := s.profilesRepo.GetByUserID(ctx, userID)
	name := "Someone"
	if err == nil && sender.FullName != nil && *sender.FullName != "" {
		name = *sender.FullName
	}

	return s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
		UserID: interest.ReceiverUserID,
		Type:   "interest_reminder",
		Title:  "Reminder",
		Body:   name + " is still waiting for your response.",
		Data:   map[string]any{"interest_id": interest.ID},
	})
}

func toResponse(i Interest) Response {
	var respondedAt *string
	if i.RespondedAt != nil {
		s := i.RespondedAt.Format(time.RFC3339)
		respondedAt = &s
	}
	var viewedAt *string
	if i.ViewedAt != nil {
		v := i.ViewedAt.Format(time.RFC3339)
		viewedAt = &v
	}
	return Response{
		ID:             i.ID,
		SenderUserID:   i.SenderUserID,
		ReceiverUserID: i.ReceiverUserID,
		Status:         i.Status,
		CreatedAt:      i.CreatedAt.Format(time.RFC3339),
		RespondedAt:    respondedAt,
		ViewedAt:       viewedAt,
	}
}

func toResponseListWithProfile(rows []InterestWithProfile) []Response {
	out := make([]Response, 0, len(rows))
	for _, r := range rows {
		resp := toResponse(r.Interest)
		resp.ProfileID = r.ProfileID
		resp.FullName = r.FullName
		resp.Gender = r.Gender
		resp.City = r.City
		resp.State = r.State
		resp.MotherTongue = r.MotherTongue
		resp.Community = r.Community
		resp.PhotoURL = r.PhotoURL
		resp.Age = ageFromDOB(r.DateOfBirth)
		resp.HeightCM = r.HeightCM
		resp.MaritalStatus = r.MaritalStatus
		resp.Religion = r.Religion
		resp.Education = r.Education
		resp.Occupation = r.Occupation
		resp.Diet = r.Diet
		resp.Manglik = r.Manglik
		out = append(out, resp)
	}
	return out
}
