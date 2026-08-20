package profiles

import "time"

type Profile struct {
	ID     string
	UserID string

	// GPS coordinates for "Near Me" — both nil until the client explicitly
	// shares a location via UpdateLocation.
	Latitude  *float64
	Longitude *float64

	FullName      *string
	DateOfBirth   *time.Time
	Gender        *string
	HeightCM      *int16
	MaritalStatus *string

	Religion     *string
	Community    *string
	MotherTongue *string

	Education       *string
	Occupation      *string
	AnnualIncomeINR *int64

	Country *string
	State   *string
	City    *string

	FamilyType       *string
	FamilyStatus     *string
	FatherOccupation *string
	MotherOccupation *string
	SiblingsCount    *int16

	Diet     *string
	Smoking  *string
	Drinking *string
	AboutMe  *string

	ProfileFor        *string
	SubCommunity      *string
	CasteNoBar        *bool
	College           *string
	WorkWith          *string
	CompanyName       *string
	MatchmakingOptOut bool
	FamilyValues      *string
	LivesWithFamily   *bool
	Hobbies           []string
	SelfieVerified    bool
	Manglik           *string
	Rashi             *string
	Nakshatra         *string
	BirthTime         *string
	BirthPlace        *string
	WeightKG          *int16
	BodyType          *string
	Complexion        *string
	HasDisability     *bool

	Visibility  string
	ProfileCode string

	CreatedAt time.Time
	UpdatedAt time.Time
}

type Photo struct {
	ID        string
	ProfileID string
	ObjectKey string
	URL       string
	IsPrimary bool
	SortOrder int16
	CreatedAt time.Time
}
