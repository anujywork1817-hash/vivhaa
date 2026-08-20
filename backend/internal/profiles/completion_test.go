package profiles

import (
	"testing"
	"time"
)

func str(s string) *string { return &s }

// fullProfile has every field CalculateCompletion scores set, so tests can
// start from 100% and remove one thing at a time.
func fullProfile() Profile {
	dob := time.Date(1996, time.April, 12, 0, 0, 0, 0, time.UTC)
	income := int64(1200000)
	height := int16(178)
	return Profile{
		FullName:        str("Asha Verma"),
		DateOfBirth:     &dob,
		Gender:          str("female"),
		HeightCM:        &height,
		MaritalStatus:   str("never_married"),
		Religion:        str("Hindu"),
		Community:       str("Maratha"),
		MotherTongue:    str("Marathi"),
		Education:       str("B.Tech"),
		Occupation:      str("Software Engineer"),
		AnnualIncomeINR: &income,
		Country:         str("India"),
		State:           str("Maharashtra"),
		City:            str("Pune"),
		FamilyType:      str("nuclear"),
		FamilyStatus:    str("middle_class"),
		Diet:            str("vegetarian"),
		AboutMe:         str("Loves hiking and cooking."),
	}
}

func TestCalculateCompletion_Bounds(t *testing.T) {
	if got := CalculateCompletion(Profile{}, 0); got != 0 {
		t.Errorf("empty profile with no photos = %d, want 0", got)
	}
	if got := CalculateCompletion(fullProfile(), 1); got != 100 {
		t.Errorf("fully filled profile with a photo = %d, want 100", got)
	}
}

// A photo is one of the scored items, so a complete profile without one
// must not read as 100%.
func TestCalculateCompletion_PhotoCounts(t *testing.T) {
	withPhoto := CalculateCompletion(fullProfile(), 1)
	without := CalculateCompletion(fullProfile(), 0)

	if without >= withPhoto {
		t.Fatalf("missing photo did not lower completion: with=%d without=%d", withPhoto, without)
	}
	// Extra photos beyond the first don't add score — the check is
	// "has at least one".
	if many := CalculateCompletion(fullProfile(), 6); many != withPhoto {
		t.Errorf("6 photos = %d, want same as 1 photo (%d)", many, withPhoto)
	}
}

// Empty strings are "not filled in", not "filled in with nothing" —
// otherwise a blank field would inflate the score.
func TestCalculateCompletion_EmptyStringsDoNotCount(t *testing.T) {
	blank := fullProfile()
	blank.FullName = str("")
	blank.Religion = str("")
	blank.City = str("")

	full := CalculateCompletion(fullProfile(), 1)
	got := CalculateCompletion(blank, 1)

	if got >= full {
		t.Fatalf("blank string fields counted as filled: got %d, full %d", got, full)
	}
}

func TestCalculateCompletion_IncreasesMonotonically(t *testing.T) {
	dob := time.Date(1996, time.April, 12, 0, 0, 0, 0, time.UTC)

	stages := []struct {
		name string
		p    Profile
	}{
		{name: "empty", p: Profile{}},
		{name: "name only", p: Profile{FullName: str("Asha Verma")}},
		{name: "name+dob", p: Profile{FullName: str("Asha Verma"), DateOfBirth: &dob}},
		{
			name: "name+dob+gender",
			p:    Profile{FullName: str("Asha Verma"), DateOfBirth: &dob, Gender: str("female")},
		},
	}

	previous := -1
	for _, stage := range stages {
		got := CalculateCompletion(stage.p, 0)
		if got <= previous {
			t.Fatalf("%s: completion %d did not increase over previous %d", stage.name, got, previous)
		}
		if got < 0 || got > 100 {
			t.Fatalf("%s: completion %d out of range", stage.name, got)
		}
		previous = got
	}
}
