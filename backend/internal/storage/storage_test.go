package storage

import "testing"

// fixture builds a byte slice of exactly size bytes starting with header —
// real magic bytes followed by padding, so ValidateImage/ValidateDocument's
// content-sniffing check (not just size/content-type) passes for the
// "should be accepted" cases.
func fixture(header []byte, size int) []byte {
	b := make([]byte, size)
	copy(b, header)
	return b
}

var (
	jpegHeader = []byte{0xFF, 0xD8, 0xFF, 0xE0}
	pngHeader  = []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
	webpHeader = append(append([]byte("RIFF"), 0, 0, 0, 0), []byte("WEBP")...)
	pdfHeader  = []byte("%PDF-1.4\n")
)

// The upload path rejects anything that isn't a recognised image type —
// and, since real magic bytes are now required too, anything whose
// content doesn't actually match its claimed type. This is the check
// that made every profile-photo upload fail while the mobile client was
// sending application/octet-stream, so the accepted and rejected sets
// are both pinned here deliberately.
func TestValidateImage_ContentTypes(t *testing.T) {
	tests := []struct {
		name        string
		data        []byte
		contentType string
		wantErr     bool
	}{
		{name: "jpeg accepted", data: fixture(jpegHeader, 1024), contentType: "image/jpeg"},
		{name: "png accepted", data: fixture(pngHeader, 1024), contentType: "image/png"},
		{name: "webp accepted", data: fixture(webpHeader, 1024), contentType: "image/webp"},

		{name: "octet-stream rejected", data: fixture(jpegHeader, 1024), contentType: "application/octet-stream", wantErr: true},
		{name: "gif rejected", data: fixture(jpegHeader, 1024), contentType: "image/gif", wantErr: true},
		{name: "pdf rejected", data: fixture(pdfHeader, 1024), contentType: "application/pdf", wantErr: true},
		{name: "empty rejected", data: fixture(jpegHeader, 1024), contentType: "", wantErr: true},
		// Callers must normalise before validating; a raw header value
		// carrying parameters is not silently accepted.
		{name: "jpeg with charset param rejected", data: fixture(jpegHeader, 1024), contentType: "image/jpeg; charset=utf-8", wantErr: true},
		// Content doesn't match the claimed type — an HTML/script payload
		// claiming to be a jpeg must be rejected even though the
		// content-type header and size are both individually "valid".
		{name: "html claiming jpeg rejected", data: fixture([]byte("<script>alert(1)</script>"), 1024), contentType: "image/jpeg", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateImage(tt.data, tt.contentType)
			if tt.wantErr && err == nil {
				t.Fatalf("ValidateImage(..., %q) = nil, want error", tt.contentType)
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("ValidateImage(..., %q) = %v, want nil", tt.contentType, err)
			}
		})
	}
}

func TestValidateImage_SizeLimit(t *testing.T) {
	if err := ValidateImage(fixture(jpegHeader, MaxPhotoSizeBytes), "image/jpeg"); err != nil {
		t.Fatalf("size exactly at the limit should be allowed, got %v", err)
	}
	if err := ValidateImage(fixture(jpegHeader, MaxPhotoSizeBytes+1), "image/jpeg"); err == nil {
		t.Fatal("size one byte over the limit should be rejected")
	}
}

// Size is checked before content type, so an oversized upload is rejected
// even when the type would otherwise be fine.
func TestValidateImage_OversizedValidTypeStillRejected(t *testing.T) {
	if err := ValidateImage(fixture(pngHeader, MaxPhotoSizeBytes*2), "image/png"); err == nil {
		t.Fatal("oversized png should be rejected")
	}
}

func TestValidateDocument(t *testing.T) {
	tests := []struct {
		name        string
		data        []byte
		contentType string
		wantErr     bool
	}{
		{name: "jpeg", data: fixture(jpegHeader, 1024), contentType: "image/jpeg"},
		{name: "png", data: fixture(pngHeader, 1024), contentType: "image/png"},
		{name: "pdf", data: fixture(pdfHeader, 1024), contentType: "application/pdf"},
		{name: "octet-stream rejected", data: fixture(pdfHeader, 1024), contentType: "application/octet-stream", wantErr: true},
		{name: "empty rejected", data: fixture(pdfHeader, 1024), contentType: "", wantErr: true},
		{name: "html claiming pdf rejected", data: fixture([]byte("<html>not a pdf</html>"), 1024), contentType: "application/pdf", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateDocument(tt.data, tt.contentType)
			if tt.wantErr && err == nil {
				t.Fatalf("ValidateDocument(..., %q) = nil, want error", tt.contentType)
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("ValidateDocument(..., %q) = %v, want nil", tt.contentType, err)
			}
		})
	}
}
