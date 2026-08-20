package recommendation

type MatchResponse struct {
	ProfileID          string  `json:"profile_id"`
	FullName           *string `json:"full_name"`
	City               *string `json:"city"`
	State              *string `json:"state,omitempty"`
	MotherTongue       *string `json:"mother_tongue,omitempty"`
	Religion           *string `json:"religion"`
	PhotoURL           *string `json:"photo_url"`
	CompatibilityScore int     `json:"compatibility_score"`
	Age                *int    `json:"age,omitempty"`
	HeightCM           *int16  `json:"height_cm,omitempty"`
	MaritalStatus      *string `json:"marital_status,omitempty"`
	Education          *string `json:"education,omitempty"`
	Occupation         *string `json:"occupation,omitempty"`
	Diet               *string `json:"diet,omitempty"`
	Manglik            *string `json:"manglik,omitempty"`
}

type NearbyMatchResponse struct {
	MatchResponse
	DistanceKM float64 `json:"distance_km"`
}
