package shortlisted

import "time"

type Shortlisted struct {
	ID           string
	UserID       string
	TargetUserID string
	CreatedAt    time.Time
}

// ShortlistedWithProfile joins a shortlist entry with a brief of the
// target's profile.
type ShortlistedWithProfile struct {
	Shortlisted
	ProfileID     string
	FullName      *string
	City          *string
	PhotoURL      *string
	DateOfBirth   *time.Time
	HeightCM      *int16
	MaritalStatus *string
	Religion      *string
	Education     *string
	Occupation    *string
	Diet          *string
	Manglik       *string
}

// ageFromDOB returns the whole-years age for a date of birth, or nil.
func ageFromDOB(dob *time.Time) *int {
	if dob == nil {
		return nil
	}
	years := int(time.Since(*dob).Hours() / 24 / 365.25)
	return &years
}
