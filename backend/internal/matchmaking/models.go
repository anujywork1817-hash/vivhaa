package matchmaking

import "time"

// Candidate is a profile in the eligible pool for matching, carrying just
// the fields the scoring function and match list responses need.
type Candidate struct {
	ProfileID       string
	UserID          string
	FullName        *string
	DateOfBirth     *time.Time
	Gender          *string
	Religion        *string
	Community       *string
	City            *string
	State           *string
	MotherTongue    *string
	Diet            *string
	MaritalStatus   *string
	AnnualIncomeINR *int64
	PhotoURL        *string
	HeightCM        *int16
	Education       *string
	Occupation      *string
	Manglik         *string
}
