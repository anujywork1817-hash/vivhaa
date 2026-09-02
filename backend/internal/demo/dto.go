package demo

// SwipeDeckCard mirrors recommendation.MatchResponse's shape (minus the
// compatibility score, which is meaningless for the fixed demo pool) so
// the Flutter side can reuse its existing discover-matches card widget
// close to as-is.
type SwipeDeckCard struct {
	ProfileID     string  `json:"profile_id"`
	FullName      *string `json:"full_name"`
	City          *string `json:"city"`
	State         *string `json:"state,omitempty"`
	MotherTongue  *string `json:"mother_tongue,omitempty"`
	Religion      *string `json:"religion"`
	PhotoURL      *string `json:"photo_url"`
	Age           *int    `json:"age,omitempty"`
	HeightCM      *int16  `json:"height_cm,omitempty"`
	MaritalStatus *string `json:"marital_status,omitempty"`
	Education     *string `json:"education,omitempty"`
	Occupation    *string `json:"occupation,omitempty"`
	Diet          *string `json:"diet,omitempty"`
	// IsDemo is always true here — included explicitly so the client never
	// has to guess/assume, and can assert it defensively.
	IsDemo bool `json:"is_demo"`
}
