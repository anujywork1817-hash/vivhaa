package interests

import "time"

// ageFromDOB returns the whole-years age for a date of birth, or nil.
func ageFromDOB(dob *time.Time) *int {
	if dob == nil {
		return nil
	}
	years := int(time.Since(*dob).Hours() / 24 / 365.25)
	return &years
}

type Interest struct {
	ID             string
	SenderUserID   string
	ReceiverUserID string
	Status         string
	CreatedAt      time.Time
	RespondedAt    *time.Time
	ViewedAt       *time.Time
}

// InterestWithProfile joins an interest with a brief of the *other*
// party's profile, for list views.
type InterestWithProfile struct {
	Interest
	ProfileID     string
	FullName      *string
	Gender        *string
	City          *string
	State         *string
	MotherTongue  *string
	Community     *string
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
