package preferences

import "fmt"

type UpsertRequest struct {
	MinAge      *int16 `json:"min_age" validate:"omitempty,gte=18,lte=100"`
	MaxAge      *int16 `json:"max_age" validate:"omitempty,gte=18,lte=100"`
	MinHeightCM *int16 `json:"min_height_cm" validate:"omitempty,gte=100,lte=250"`
	MaxHeightCM *int16 `json:"max_height_cm" validate:"omitempty,gte=100,lte=250"`

	MaritalStatus []string `json:"marital_status" validate:"omitempty,max=50,dive,max=100"`
	Religion      []string `json:"religion" validate:"omitempty,max=50,dive,max=100"`
	Community     []string `json:"community" validate:"omitempty,max=50,dive,max=100"`
	MotherTongue  []string `json:"mother_tongue" validate:"omitempty,max=50,dive,max=100"`
	Education     []string `json:"education" validate:"omitempty,max=50,dive,max=100"`
	MinIncomeINR  *int64   `json:"min_income_inr" validate:"omitempty,gte=0"`
	Country       []string `json:"country" validate:"omitempty,max=50,dive,max=100"`
	State         []string `json:"state" validate:"omitempty,max=50,dive,max=100"`
	City          []string `json:"city" validate:"omitempty,max=50,dive,max=100"`
	Diet          []string `json:"diet" validate:"omitempty,max=50,dive,max=100"`

	Profession       *string `json:"profession" validate:"omitempty,max=150"`
	WorkingWith      *string `json:"working_with" validate:"omitempty,max=50"`
	ProfileManagedBy *string `json:"profile_managed_by" validate:"omitempty,max=30"`

	AboutPartner *string `json:"about_partner" validate:"omitempty,max=2000"`
}

// Validate does the cross-field checks struct tags can't express safely
// for optional (pointer) fields — go-playground/validator's ltefield/
// gtefield cross-field tags don't nil-check the compared field first, so
// e.g. min_age with no max_age set would compare against a phantom zero
// value instead of just skipping the check. Called manually by the
// handler after validator.Struct passes. Without this, a client could
// submit min_age=80/max_age=18 — a preferences row that will never match
// anyone — or an inverted height range.
func (r *UpsertRequest) Validate() error {
	if r.MinAge != nil && r.MaxAge != nil && *r.MinAge > *r.MaxAge {
		return fmt.Errorf("min_age must be less than or equal to max_age")
	}
	if r.MinHeightCM != nil && r.MaxHeightCM != nil && *r.MinHeightCM > *r.MaxHeightCM {
		return fmt.Errorf("min_height_cm must be less than or equal to max_height_cm")
	}
	return nil
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
