// Package storage provides domain-level helpers over pkg/s3 for uploading
// user-generated files (profile photos, verification docs) with
// consistent key naming and basic validation.
package storage

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"matrimony-backend/pkg/s3"
)

var allowedImageTypes = map[string]string{
	"image/jpeg": ".jpg",
	"image/png":  ".png",
	"image/webp": ".webp",
}

const MaxPhotoSizeBytes = 5 * 1024 * 1024 // 5MB

type PhotoUploader struct {
	client *s3.Client
}

func NewPhotoUploader(client *s3.Client) *PhotoUploader {
	return &PhotoUploader{client: client}
}

// ValidateImage checks size and content-type before an upload is attempted.
func ValidateImage(size int64, contentType string) error {
	if size > MaxPhotoSizeBytes {
		return fmt.Errorf("file too large: max %d bytes", MaxPhotoSizeBytes)
	}
	if _, ok := allowedImageTypes[contentType]; !ok {
		return fmt.Errorf("unsupported content type %q: allowed jpeg, png, webp", contentType)
	}
	return nil
}

// UploadProfilePhoto uploads a validated image under a per-user prefix and
// returns its object key and public URL.
func (u *PhotoUploader) UploadProfilePhoto(ctx context.Context, userID string, data []byte, contentType string) (key, url string, err error) {
	ext := allowedImageTypes[contentType]
	key = fmt.Sprintf("profiles/%s/%s%s", userID, uuid.NewString(), ext)

	url, err = u.client.Upload(ctx, key, data, contentType)
	if err != nil {
		return "", "", err
	}
	return key, url, nil
}

func (u *PhotoUploader) Delete(ctx context.Context, key string) error {
	return u.client.Delete(ctx, key)
}

var allowedDocumentTypes = map[string]string{
	"image/jpeg":      ".jpg",
	"image/png":       ".png",
	"application/pdf": ".pdf",
}

const MaxDocumentSizeBytes = 10 * 1024 * 1024 // 10MB

type DocumentUploader struct {
	client *s3.Client
}

func NewDocumentUploader(client *s3.Client) *DocumentUploader {
	return &DocumentUploader{client: client}
}

// ValidateDocument checks size and content-type before an upload is attempted.
func ValidateDocument(size int64, contentType string) error {
	if size > MaxDocumentSizeBytes {
		return fmt.Errorf("file too large: max %d bytes", MaxDocumentSizeBytes)
	}
	if _, ok := allowedDocumentTypes[contentType]; !ok {
		return fmt.Errorf("unsupported content type %q: allowed jpeg, png, pdf", contentType)
	}
	return nil
}

// DocumentURLTTL is how long a signed document-view URL stays valid.
// Short enough that a leaked link (browser history, proxy log, screen
// share) is only a narrow window of exposure — long enough to actually
// load and review a document without re-signing mid-review.
const DocumentURLTTL = 15 * time.Minute

// UploadVerificationDoc uploads a validated ID document under a per-user
// prefix into the private verification-documents bucket and returns its
// object key. There is no URL to return: the bucket has no public-read
// access, so a document is only ever viewable via a short-lived signed
// URL minted on demand — see PresignURL.
func (u *DocumentUploader) UploadVerificationDoc(ctx context.Context, userID string, data []byte, contentType string) (key string, err error) {
	ext := allowedDocumentTypes[contentType]
	key = fmt.Sprintf("verifications/%s/%s%s", userID, uuid.NewString(), ext)

	if err := u.client.UploadDoc(ctx, key, data, contentType); err != nil {
		return "", err
	}
	return key, nil
}

// PresignURL mints a fresh, time-limited signed URL for viewing a
// verification document. Call this at read time (e.g. when an admin
// opens the verification queue or a detail view) — never store the
// result, since it expires after DocumentURLTTL.
func (u *DocumentUploader) PresignURL(ctx context.Context, key string) (string, error) {
	return u.client.PresignDocURL(ctx, key, DocumentURLTTL)
}

func (u *DocumentUploader) DeleteDoc(ctx context.Context, key string) error {
	return u.client.DeleteDoc(ctx, key)
}
