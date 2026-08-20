package verification

import (
	"context"
	"errors"
	"fmt"
	"time"

	"matrimony-backend/internal/storage"
)

var (
	ErrInvalidDocumentType = errors.New("invalid document type")
	ErrInvalidFile         = errors.New("invalid file")
	ErrAlreadyPending      = errors.New("a verification request is already pending review")
	ErrAlreadyApproved     = errors.New("your identity is already verified")
)

// ProfileVerifier flips a profile's verified badge — declared locally
// (rather than importing *profiles.Repository's concrete type) to avoid
// an import cycle; *profiles.Repository satisfies this structurally.
type ProfileVerifier interface {
	SetSelfieVerified(ctx context.Context, userID string, verified bool) error
}

var validDocumentTypes = map[string]bool{
	"aadhaar":         true,
	"passport":        true,
	"driving_license": true,
	"voter_id":        true,
	"pan":               true,
	"selfie":            true,
	"personal_document": true,
}

type Service struct {
	repo            *Repository
	uploader        *storage.DocumentUploader
	profileVerifier ProfileVerifier
}

func NewService(repo *Repository, uploader *storage.DocumentUploader, profileVerifier ProfileVerifier) *Service {
	return &Service{repo: repo, uploader: uploader, profileVerifier: profileVerifier}
}

func (s *Service) Submit(ctx context.Context, userID, documentType string, data []byte, contentType string) (Response, error) {
	if !validDocumentTypes[documentType] {
		return Response{}, ErrInvalidDocumentType
	}
	if err := storage.ValidateDocument(int64(len(data)), contentType); err != nil {
		return Response{}, fmt.Errorf("%w: %v", ErrInvalidFile, err)
	}

	existing, err := s.repo.GetLatestByUserIDAndType(ctx, userID, documentType)
	if err == nil {
		if existing.Status == "pending" {
			return Response{}, ErrAlreadyPending
		}
		if existing.Status == "approved" {
			return Response{}, ErrAlreadyApproved
		}
	} else if !errors.Is(err, ErrNotFound) {
		return Response{}, err
	}

	key, err := s.uploader.UploadVerificationDoc(ctx, userID, data, contentType)
	if err != nil {
		return Response{}, err
	}

	v, err := s.repo.Create(ctx, userID, documentType, key)
	if err != nil {
		return Response{}, err
	}
	return s.toResponse(ctx, v)
}

func (s *Service) GetMine(ctx context.Context, userID string) (Response, error) {
	v, err := s.repo.GetLatestByUserID(ctx, userID)
	if err != nil {
		return Response{}, err
	}
	return s.toResponse(ctx, v)
}

// ListByUserID returns every document submitted by userID, newest first.
// Used both for a user's own document list and, with an admin-supplied
// userID, for the admin per-customer documents view.
func (s *Service) ListByUserID(ctx context.Context, userID string) ([]Response, error) {
	rows, err := s.repo.ListByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]Response, 0, len(rows))
	for _, v := range rows {
		resp, err := s.toResponse(ctx, v)
		if err != nil {
			return nil, err
		}
		out = append(out, resp)
	}
	return out, nil
}

const (
	defaultLimit = 20
	maxLimit     = 100
)

func (s *Service) ListPending(ctx context.Context, page, limit int) ([]Response, ListMeta, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = defaultLimit
	}
	if limit > maxLimit {
		limit = maxLimit
	}

	total, err := s.repo.CountByStatus(ctx, "pending")
	if err != nil {
		return nil, ListMeta{}, err
	}

	rows, err := s.repo.ListByStatus(ctx, "pending", limit, (page-1)*limit)
	if err != nil {
		return nil, ListMeta{}, err
	}
	out := make([]Response, 0, len(rows))
	for _, v := range rows {
		resp, err := s.toResponse(ctx, v)
		if err != nil {
			return nil, ListMeta{}, err
		}
		out = append(out, resp)
	}
	return out, ListMeta{Page: page, Limit: limit, Total: total}, nil
}

func (s *Service) Approve(ctx context.Context, id, reviewerID string, notes *string) (Response, error) {
	return s.review(ctx, id, "approved", reviewerID, notes)
}

func (s *Service) Reject(ctx context.Context, id, reviewerID string, notes *string) (Response, error) {
	return s.review(ctx, id, "rejected", reviewerID, notes)
}

func (s *Service) review(ctx context.Context, id, status, reviewerID string, notes *string) (Response, error) {
	v, err := s.repo.Review(ctx, id, status, reviewerID, notes)
	if err != nil {
		return Response{}, err
	}
	// BUG-C05: approval must actually flip the profile's verified badge —
	// previously this only updated the verifications row, leaving the
	// (also-fixed) user-settable profiles.selfie_verified field as the
	// only thing that ever controlled the badge.
	if status == "approved" {
		if err := s.profileVerifier.SetSelfieVerified(ctx, v.UserID, true); err != nil {
			return Response{}, fmt.Errorf("set profile verified: %w", err)
		}
	}
	return s.toResponse(ctx, v)
}

// toResponse mints a fresh, short-lived signed URL for the document on
// every call rather than reading any URL out of the DB — see BUG-C06:
// verification documents live in a private bucket now, so the only way
// to view one is a signed URL generated at read time (here), never a
// permanently stored public link.
func (s *Service) toResponse(ctx context.Context, v Verification) (Response, error) {
	var reviewedAt *string
	if v.ReviewedAt != nil {
		s := v.ReviewedAt.Format(time.RFC3339)
		reviewedAt = &s
	}
	docURL, err := s.uploader.PresignURL(ctx, v.DocumentKey)
	if err != nil {
		return Response{}, fmt.Errorf("presign document url: %w", err)
	}
	return Response{
		ID:           v.ID,
		UserID:       v.UserID,
		DocumentType: v.DocumentType,
		DocumentURL:  docURL,
		Status:       v.Status,
		ReviewNotes:  v.ReviewNotes,
		CreatedAt:    v.CreatedAt.Format(time.RFC3339),
		ReviewedAt:   reviewedAt,
	}, nil
}
