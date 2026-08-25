// Package storage provides domain-level helpers over pkg/s3 for uploading
// user-generated files (profile photos, verification docs) with
// consistent key naming and basic validation.
package storage

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"

	"matrimony-backend/pkg/s3"
)

// sniffMatchesClaim reports whether data's actual content plausibly
// matches claimedType, using the file's own magic bytes rather than
// trusting the client-supplied Content-Type header on its own — a
// request can set that header to anything regardless of what the bytes
// actually are. http.DetectContentType covers jpeg/png/pdf directly;
// webp and the Office document formats need their own signature checks
// since Go's sniffer doesn't recognize those.
func sniffMatchesClaim(data []byte, claimedType string) bool {
	switch claimedType {
	case "image/jpeg", "image/png", "application/pdf":
		return http.DetectContentType(data) == claimedType
	case "image/webp":
		// RIFF....WEBP
		return len(data) >= 12 && bytes.Equal(data[0:4], []byte("RIFF")) && bytes.Equal(data[8:12], []byte("WEBP"))
	case "application/msword":
		// Old binary Office compound-file signature (also covers legacy
		// .xls/.ppt, but this app only ever names this type .doc).
		return len(data) >= 8 && bytes.Equal(data[0:8], []byte{0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1})
	case "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
		// .docx is a ZIP container ("PK\x03\x04" local-file-header magic);
		// verifying the internal XML parts would need actually opening the
		// zip, which is more than a content-type-spoofing check needs.
		return len(data) >= 4 && bytes.Equal(data[0:4], []byte{0x50, 0x4B, 0x03, 0x04})
	default:
		return false
	}
}

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

// ValidateImage checks size, claimed content-type, and — critically —
// that data's actual magic bytes match that claim, before an upload is
// attempted. Trusting the client-supplied Content-Type header alone (as
// this used to) lets an attacker upload anything (a script/HTML payload,
// say) while just claiming image/jpeg; these go to a PUBLIC bucket
// (profile photos), so a content-type mismatch here is a real stored-
// content-confusion / XSS-adjacent risk if such a file is ever served
// inline as if it were the image it claims to be.
func ValidateImage(data []byte, contentType string) error {
	if int64(len(data)) > MaxPhotoSizeBytes {
		return fmt.Errorf("file too large: max %d bytes", MaxPhotoSizeBytes)
	}
	if _, ok := allowedImageTypes[contentType]; !ok {
		return fmt.Errorf("unsupported content type %q: allowed jpeg, png, webp", contentType)
	}
	if !sniffMatchesClaim(data, contentType) {
		return fmt.Errorf("file content does not match claimed type %q", contentType)
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

// PublicURL rebuilds key's URL from the live S3 config — see s3.Client.PublicURL.
func (u *PhotoUploader) PublicURL(key string) string {
	return u.client.PublicURL(key)
}

func (u *PhotoUploader) Delete(ctx context.Context, key string) error {
	return u.client.Delete(ctx, key)
}

// allowedChatAttachmentTypes covers both images and simple documents —
// chat attachments aren't identity documents (unlike verification docs),
// so they go through the same public-bucket path as profile photos
// rather than the private, presigned-URL-only document bucket.
var allowedChatAttachmentTypes = map[string]string{
	"image/jpeg":         ".jpg",
	"image/png":          ".png",
	"image/webp":         ".webp",
	"application/pdf":    ".pdf",
	"application/msword": ".doc",
	"application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
}

const MaxChatAttachmentSizeBytes = 15 * 1024 * 1024 // 15MB

// ValidateChatAttachment checks size and content-type before an upload is
// attempted, and reports whether the type is an image (vs. a document) —
// the chat message Kind (image vs document) is picked from this rather
// than trusting a client-supplied field.
func ValidateChatAttachment(data []byte, contentType string) (isImage bool, err error) {
	if int64(len(data)) > MaxChatAttachmentSizeBytes {
		return false, fmt.Errorf("file too large: max %d bytes", MaxChatAttachmentSizeBytes)
	}
	if _, ok := allowedChatAttachmentTypes[contentType]; !ok {
		return false, fmt.Errorf("unsupported content type %q", contentType)
	}
	if !sniffMatchesClaim(data, contentType) {
		return false, fmt.Errorf("file content does not match claimed type %q", contentType)
	}
	return contentType == "image/jpeg" || contentType == "image/png" || contentType == "image/webp", nil
}

// UploadChatAttachment uploads a validated image/document under a
// per-user prefix and returns its object key and public URL.
func (u *PhotoUploader) UploadChatAttachment(ctx context.Context, userID string, data []byte, contentType string) (key, url string, err error) {
	ext := allowedChatAttachmentTypes[contentType]
	key = fmt.Sprintf("chat/%s/%s%s", userID, uuid.NewString(), ext)

	url, err = u.client.Upload(ctx, key, data, contentType)
	if err != nil {
		return "", "", err
	}
	return key, url, nil
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
func ValidateDocument(data []byte, contentType string) error {
	if int64(len(data)) > MaxDocumentSizeBytes {
		return fmt.Errorf("file too large: max %d bytes", MaxDocumentSizeBytes)
	}
	if _, ok := allowedDocumentTypes[contentType]; !ok {
		return fmt.Errorf("unsupported content type %q: allowed jpeg, png, pdf", contentType)
	}
	if !sniffMatchesClaim(data, contentType) {
		return fmt.Errorf("file content does not match claimed type %q", contentType)
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
