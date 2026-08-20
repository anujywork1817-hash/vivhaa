package interests

type Response struct {
	ID             string  `json:"id"`
	SenderUserID   string  `json:"sender_user_id"`
	ReceiverUserID string  `json:"receiver_user_id"`
	Status         string  `json:"status"`
	CreatedAt      string  `json:"created_at"`
	RespondedAt    *string `json:"responded_at"`
	ViewedAt       *string `json:"viewed_at"`

	ProfileID     string  `json:"profile_id,omitempty"`
	FullName      *string `json:"full_name,omitempty"`
	Gender        *string `json:"gender,omitempty"`
	City          *string `json:"city,omitempty"`
	State         *string `json:"state,omitempty"`
	MotherTongue  *string `json:"mother_tongue,omitempty"`
	Community     *string `json:"community,omitempty"`
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
