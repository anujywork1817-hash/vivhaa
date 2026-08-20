package search

type Query struct {
	MinAge        *int     `form:"min_age"`
	MaxAge        *int     `form:"max_age"`
	Gender        *string  `form:"gender"`
	MaritalStatus []string `form:"marital_status"`
	Religion      []string `form:"religion"`
	Community     []string `form:"community"`
	Education     []string `form:"education"`
	Occupation    []string `form:"occupation"`
	City          *string  `form:"city"`
	State         *string  `form:"state"`
	MinIncomeINR  *int64   `form:"min_income_inr"`
	MaxIncomeINR  *int64   `form:"max_income_inr"`
	Diet          []string `form:"diet"`
	Manglik       *string  `form:"manglik"`
	MinHeightCM   *int     `form:"min_height_cm"`
	MaxHeightCM   *int     `form:"max_height_cm"`
	Query         *string  `form:"q"`
	Page          int      `form:"page"`
	Limit         int      `form:"limit"`
}

type ProfileResult struct {
	ProfileID     string  `json:"profile_id"`
	ProfileCode   string  `json:"profile_code"`
	FullName      *string `json:"full_name"`
	Age           *int    `json:"age"`
	Gender        *string `json:"gender"`
	Religion      *string `json:"religion"`
	Community     *string `json:"community"`
	Education     *string `json:"education"`
	Occupation    *string `json:"occupation"`
	City          *string `json:"city"`
	State         *string `json:"state"`
	PhotoURL      *string `json:"photo_url"`
	HeightCM      *int16  `json:"height_cm,omitempty"`
	MaritalStatus *string `json:"marital_status,omitempty"`
	Diet          *string `json:"diet,omitempty"`
	Manglik       *string `json:"manglik,omitempty"`
}

type Meta struct {
	Page  int `json:"page"`
	Limit int `json:"limit"`
	Total int `json:"total"`
}
