package devices

import (
	"errors"
	"testing"
)

// validate exercises the input rules directly — Register itself needs a
// live database, but normalisation is where the interesting logic is.
func validate(token, platform string) (string, string, error) {
	s := &Service{}
	return s.normalise(token, platform)
}

func TestNormalise_RejectsEmptyToken(t *testing.T) {
	for _, token := range []string{"", "   ", "\t\n"} {
		if _, _, err := validate(token, "android"); !errors.Is(err, ErrTokenRequired) {
			t.Errorf("token %q: got %v, want ErrTokenRequired", token, err)
		}
	}
}

func TestNormalise_TrimsToken(t *testing.T) {
	got, _, err := validate("  fcm-token-123  ", "android")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "fcm-token-123" {
		t.Errorf("token = %q, want %q", got, "fcm-token-123")
	}
}

// Platform is optional from the client's point of view; Android is the
// only shipping target today, so that's the default.
func TestNormalise_DefaultsPlatform(t *testing.T) {
	_, platform, err := validate("token", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if platform != "android" {
		t.Errorf("platform = %q, want android", platform)
	}
}

func TestNormalise_AcceptsKnownPlatformsCaseInsensitively(t *testing.T) {
	for _, in := range []string{"android", "iOS", "WEB", "Android"} {
		_, platform, err := validate("token", in)
		if err != nil {
			t.Errorf("platform %q was rejected: %v", in, err)
			continue
		}
		if platform != "android" && platform != "ios" && platform != "web" {
			t.Errorf("platform %q normalised to %q, want a lowercase known value", in, platform)
		}
	}
}

func TestNormalise_RejectsUnknownPlatform(t *testing.T) {
	for _, in := range []string{"windows", "symbian", "desktop"} {
		if _, _, err := validate("token", in); !errors.Is(err, ErrInvalidPlatform) {
			t.Errorf("platform %q: got %v, want ErrInvalidPlatform", in, err)
		}
	}
}
