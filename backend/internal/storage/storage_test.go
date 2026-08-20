package storage

import "testing"

// The upload path rejects anything that isn't a recognised image type.
// This is the check that made every profile-photo upload fail while the
// mobile client was sending application/octet-stream, so the accepted and
// rejected sets are both pinned here deliberately.
func TestValidateImage_ContentTypes(t *testing.T) {
	tests := []struct {
		name        string
		contentType string
		wantErr     bool
	}{
		{name: "jpeg accepted", contentType: "image/jpeg"},
		{name: "png accepted", contentType: "image/png"},
		{name: "webp accepted", contentType: "image/webp"},

		{name: "octet-stream rejected", contentType: "application/octet-stream", wantErr: true},
		{name: "gif rejected", contentType: "image/gif", wantErr: true},
		{name: "pdf rejected", contentType: "application/pdf", wantErr: true},
		{name: "empty rejected", contentType: "", wantErr: true},
		// Callers must normalise before validating; a raw header value
		// carrying parameters is not silently accepted.
		{name: "jpeg with charset param rejected", contentType: "image/jpeg; charset=utf-8", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateImage(1024, tt.contentType)
			if tt.wantErr && err == nil {
				t.Fatalf("ValidateImage(1024, %q) = nil, want error", tt.contentType)
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("ValidateImage(1024, %q) = %v, want nil", tt.contentType, err)
			}
		})
	}
}

func TestValidateImage_SizeLimit(t *testing.T) {
	if err := ValidateImage(MaxPhotoSizeBytes, "image/jpeg"); err != nil {
		t.Fatalf("size exactly at the limit should be allowed, got %v", err)
	}
	if err := ValidateImage(MaxPhotoSizeBytes+1, "image/jpeg"); err == nil {
		t.Fatal("size one byte over the limit should be rejected")
	}
}

// Size is checked before content type, so an oversized upload is rejected
// even when the type would otherwise be fine.
func TestValidateImage_OversizedValidTypeStillRejected(t *testing.T) {
	if err := ValidateImage(MaxPhotoSizeBytes*2, "image/png"); err == nil {
		t.Fatal("oversized png should be rejected")
	}
}

func TestValidateDocument(t *testing.T) {
	tests := []struct {
		contentType string
		wantErr     bool
	}{
		{contentType: "image/jpeg"},
		{contentType: "image/png"},
		{contentType: "application/pdf"},
		{contentType: "application/octet-stream", wantErr: true},
		{contentType: "", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.contentType, func(t *testing.T) {
			err := ValidateDocument(1024, tt.contentType)
			if tt.wantErr && err == nil {
				t.Fatalf("ValidateDocument(1024, %q) = nil, want error", tt.contentType)
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("ValidateDocument(1024, %q) = %v, want nil", tt.contentType, err)
			}
		})
	}
}
