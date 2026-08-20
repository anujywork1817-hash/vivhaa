package preferences

type UpsertRequest struct {
	MinAge      *int16 `json:"min_age" validate:"omitempty,gte=18,lte=100"`
	MaxAge      *int16 `json:"max_age" validate:"omitempty,gte=18,lte=100"`
	MinHeightCM *int16 `json:"min_height_cm" validate:"omitempty,gte=100,lte=250"`
	MaxHeightCM *int16 `json:"max_height_cm" validate:"omitempty,gte=100,lte=250"`

	MaritalStatus []string `json:"marital_status"`
	Religion      []string `json:"religion"`
	Community     []string `json:"community"`
	MotherTongue  []string `json:"mother_tongue"`
	Education     []string `json:"education"`
	MinIncomeINR  *int64   `json:"min_income_inr" validate:"omitempty,gte=0"`
	Country       []string `json:"country"`
	State         []string `json:"state"`
	City          []string `json:"city"`
	Diet          []string `json:"diet"`

	Profession       *string `json:"profession" validate:"omitempty,max=150"`
	WorkingWith      *string `json:"working_with" validate:"omitempty,max=50"`
	ProfileManagedBy *string `json:"profile_managed_by" validate:"omitempty,max=30"`

	AboutPartner *string `json:"about_partner" validate:"omitempty,max=2000"`
}

type Response struct {
	ID     string `json:"id"`
	UserID string `json:"user_id"`

	MinAge      *int16 `json:"min_age"`
	MaxAge      *int16 `json:"max_age"`
	MinHeightCM *int16 `json:"min_height_cm"`
	MaxHeightCM *int16 `json:"max_height_cm"`

	MaritalStatus []string `json:"marital_status"`
	Religion      []string `json:"religion"`
	Community     []string `json:"community"`
	MotherTongue  []string `json:"mother_tongue"`
	Education     []string `json:"education"`
	MinIncomeINR  *int64   `json:"min_income_inr"`
	Country       []string `json:"country"`
	State         []string `json:"state"`
	City          []string `json:"city"`
	Diet          []string `json:"diet"`

	Profession       *string `json:"profession"`
	WorkingWith      *string `json:"working_with"`
	ProfileManagedBy *string `json:"profile_managed_by"`

	AboutPartner *string `json:"about_partner"`
	CreatedAt    string  `json:"created_at"`
	UpdatedAt    string  `json:"updated_at"`
}
