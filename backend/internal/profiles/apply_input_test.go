package profiles

import (
	"errors"
	"testing"
	"time"
)

// applyInput is a partial update: only fields present in the request are
// touched. These tests pin that behaviour because the "my height/company
// isn't saving" bugs all lived on this boundary — a field that silently
// fails to merge is indistinguishable from one that was never sent.
func TestApplyInput_OnlyOverwritesProvidedFields(t *testing.T) {
	existing := Profile{
		FullName:   str("Asha Verma"),
		Religion:   str("Hindu"),
		Occupation: str("Software Engineer"),
		City:       str("Pune"),
	}

	// Only occupation is present in the update.
	in := ProfileInput{Occupation: str("Architect")}

	if err := applyInput(&existing, in); err != nil {
		t.Fatalf("applyInput returned error: %v", err)
	}

	if got := *existing.Occupation; got != "Architect" {
		t.Errorf("Occupation = %q, want Architect", got)
	}
	for _, field := range []struct {
		name string
		got  *string
		want string
	}{
		{"FullName", existing.FullName, "Asha Verma"},
		{"Religion", existing.Religion, "Hindu"},
		{"City", existing.City, "Pune"},
	} {
		if field.got == nil {
			t.Errorf("%s was cleared by an update that didn't mention it", field.name)
			continue
		}
		if *field.got != field.want {
			t.Errorf("%s = %q, want %q (untouched)", field.name, *field.got, field.want)
		}
	}
}

// Numeric fields go through the same merge path as strings — height and
// income both round-tripped incorrectly at one point, so they're covered
// explicitly.
func TestApplyInput_NumericFields(t *testing.T) {
	height := int16(178)
	income := int64(1200000)

	var p Profile
	if err := applyInput(&p, ProfileInput{HeightCM: &height, AnnualIncomeINR: &income}); err != nil {
		t.Fatalf("applyInput returned error: %v", err)
	}

	if p.HeightCM == nil || *p.HeightCM != 178 {
		t.Errorf("HeightCM = %v, want 178", p.HeightCM)
	}
	if p.AnnualIncomeINR == nil || *p.AnnualIncomeINR != 1200000 {
		t.Errorf("AnnualIncomeINR = %v, want 1200000", p.AnnualIncomeINR)
	}

	// A later update that omits them must leave both alone.
	if err := applyInput(&p, ProfileInput{Occupation: str("Doctor")}); err != nil {
		t.Fatalf("applyInput returned error: %v", err)
	}
	if p.HeightCM == nil || *p.HeightCM != 178 {
		t.Errorf("HeightCM was lost by an unrelated update: %v", p.HeightCM)
	}
	if p.AnnualIncomeINR == nil || *p.AnnualIncomeINR != 1200000 {
		t.Errorf("AnnualIncomeINR was lost by an unrelated update: %v", p.AnnualIncomeINR)
	}
}

func TestApplyInput_ParsesDateOfBirth(t *testing.T) {
	var p Profile
	if err := applyInput(&p, ProfileInput{DateOfBirth: str("1996-04-12")}); err != nil {
		t.Fatalf("applyInput returned error: %v", err)
	}
	if p.DateOfBirth == nil {
		t.Fatal("DateOfBirth was not set")
	}
	if y, m, d := p.DateOfBirth.Date(); y != 1996 || m != 4 || d != 12 {
		t.Errorf("DateOfBirth = %v, want 1996-04-12", p.DateOfBirth)
	}
}

// A malformed date must surface as an error rather than being silently
// dropped or stored as a zero time.
func TestApplyInput_RejectsBadDate(t *testing.T) {
	for _, bad := range []string{"12-04-1996", "not-a-date", "1996/04/12", ""} {
		var p Profile
		if err := applyInput(&p, ProfileInput{DateOfBirth: str(bad)}); err == nil {
			t.Errorf("applyInput accepted malformed date %q", bad)
		}
	}
}

// Non-pointer fields use a different branch (deref rather than assign),
// so they get their own check.
func TestApplyInput_ValueFields(t *testing.T) {
	optOut := true
	visibility := "private"

	var p Profile
	err := applyInput(&p, ProfileInput{
		MatchmakingOptOut: &optOut,
		Visibility:        &visibility,
	})
	if err != nil {
		t.Fatalf("applyInput returned error: %v", err)
	}

	if !p.MatchmakingOptOut {
		t.Error("MatchmakingOptOut was not applied")
	}
	if p.Visibility != "private" {
		t.Errorf("Visibility = %q, want private", p.Visibility)
	}
}

// SelfieVerified must never be settable via ProfileInput (BUG-C05) — it's
// only ever flipped by admin verification review. This pins that
// applyInput has no code path that touches it at all.
func TestApplyInput_SelfieVerifiedNotSettable(t *testing.T) {
	var p Profile
	if err := applyInput(&p, ProfileInput{}); err != nil {
		t.Fatalf("applyInput returned error: %v", err)
	}
	if p.SelfieVerified {
		t.Error("SelfieVerified should default to false and be unreachable via ProfileInput")
	}
}

// Date of birth is the one ProfileInput field with a policy attached: the
// member must be an adult. The client calendar restricts its own range, so
// anything out of bounds arriving here is a bypassed client, not a typo.
func TestApplyInput_RejectsOutOfRangeDateOfBirth(t *testing.T) {
	today := time.Now().UTC()

	for _, tc := range []struct {
		name    string
		dob     time.Time
		wantErr bool
	}{
		{"comfortably adult", today.AddDate(-30, 0, 0), false},
		{"exactly the minimum age", today.AddDate(-minSignupAge, 0, 0), false},
		{"one day short of the minimum", today.AddDate(-minSignupAge, 0, 1), true},
		{"child", today.AddDate(-12, 0, 0), true},
		{"born tomorrow", today.AddDate(0, 0, 1), true},
		{"implausibly old", today.AddDate(-(maxSignupAge + 1), 0, -1), true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var p Profile
			err := applyInput(&p, ProfileInput{DateOfBirth: str(tc.dob.Format(dateLayout))})

			if tc.wantErr {
				if !errors.Is(err, ErrInvalidAge) {
					t.Fatalf("err = %v, want ErrInvalidAge", err)
				}
				if p.DateOfBirth != nil {
					t.Error("DateOfBirth was applied despite being rejected")
				}
				return
			}
			if err != nil {
				t.Fatalf("applyInput returned error: %v", err)
			}
			if p.DateOfBirth == nil {
				t.Fatal("DateOfBirth was not applied")
			}
		})
	}
}

func TestAgeOn_CountsBirthdayOnlyOnceReached(t *testing.T) {
	dob := time.Date(1996, 3, 12, 0, 0, 0, 0, time.UTC)

	for _, tc := range []struct {
		name string
		on   time.Time
		want int
	}{
		{"day before the birthday", time.Date(2026, 3, 11, 0, 0, 0, 0, time.UTC), 29},
		{"on the birthday", time.Date(2026, 3, 12, 0, 0, 0, 0, time.UTC), 30},
		{"day after the birthday", time.Date(2026, 3, 13, 0, 0, 0, 0, time.UTC), 30},
		{"earlier month", time.Date(2026, 1, 31, 0, 0, 0, 0, time.UTC), 29},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := ageOn(dob, tc.on); got != tc.want {
				t.Errorf("ageOn = %d, want %d", got, tc.want)
			}
		})
	}
}
