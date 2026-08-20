package shortlisted

type Response struct {
	ID           string `json:"id"`
	UserID       string `json:"user_id"`
	TargetUserID string `json:"target_user_id"`
	CreatedAt    string `json:"created_at"`

	ProfileID     string  `json:"profile_id,omitempty"`
	FullName      *string `json:"full_name,omitempty"`
	City          *string `json:"city,omitempty"`
	PhotoURL      *string `json:"photo_url,omitempty"`
	Age           *int    `json:"age,omitempty"`
	HeightCM      *int16  `json:"height_cm,omitempty"`
	MaritalStatus *string `json:"marital_status,omitempty"`
	Religion      *string `json:"religion,omitempty"`
	Education     *string `json:"education,omitempty"`
	Occupation    *string `json:"occupation,omitempty"`
	Diet          *string `json:"diet,omitempty"`
	Manglik       *string `json:"manglik,omitempty"`
}
