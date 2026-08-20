package preferences

import "time"

type Preferences struct {
	ID     string
	UserID string

	MinAge      *int16
	MaxAge      *int16
	MinHeightCM *int16
	MaxHeightCM *int16

	MaritalStatus []string
	Religion      []string
	Community     []string
	MotherTongue  []string
	Education     []string
	MinIncomeINR  *int64
	Country       []string
	State         []string
	City          []string
	Diet          []string

	Profession        *string
	WorkingWith       *string
	ProfileManagedBy  *string

	AboutPartner *string

	CreatedAt time.Time
	UpdatedAt time.Time
}
