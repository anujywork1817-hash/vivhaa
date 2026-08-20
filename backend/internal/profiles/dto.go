package profiles

// ProfileInput is shared by create and update requests. All fields are
// optional pointers: on create, a nil field is simply left NULL; on
// update, a nil field means "leave the existing value unchanged".
type ProfileInput struct {
	FullName      *string `json:"full_name" validate:"omitempty,max=150"`
	DateOfBirth   *string `json:"date_of_birth" validate:"omitempty,datetime=2006-01-02"`
	Gender        *string `json:"gender" validate:"omitempty,oneof=male female other"`
	HeightCM      *int16  `json:"height_cm" validate:"omitempty,gte=100,lte=250"`
	MaritalStatus *string `json:"marital_status" validate:"omitempty,oneof=never_married divorced widowed awaiting_divorce"`

	Religion     *string `json:"religion" validate:"omitempty,max=50"`
	Community    *string `json:"community" validate:"omitempty,max=100"`
	MotherTongue *string `json:"mother_tongue" validate:"omitempty,max=50"`

	Education       *string `json:"education" validate:"omitempty,max=150"`
	Occupation      *string `json:"occupation" validate:"omitempty,max=150"`
	AnnualIncomeINR *int64  `json:"annual_income_inr" validate:"omitempty,gte=0"`

	Country *string `json:"country" validate:"omitempty,max=100"`
	State   *string `json:"state" validate:"omitempty,max=100"`
	City    *string `json:"city" validate:"omitempty,max=100"`

	FamilyType       *string `json:"family_type" validate:"omitempty,oneof=nuclear joint"`
	FamilyStatus     *string `json:"family_status" validate:"omitempty,oneof=middle_class upper_middle_class affluent rich"`
	FatherOccupation *string `json:"father_occupation" validate:"omitempty,max=150"`
	MotherOccupation *string `json:"mother_occupation" validate:"omitempty,max=150"`
	SiblingsCount    *int16  `json:"siblings_count" validate:"omitempty,gte=0,lte=20"`

	Diet     *string `json:"diet" validate:"omitempty,oneof=vegetarian non_vegetarian eggetarian vegan jain"`
	Smoking  *string `json:"smoking" validate:"omitempty,oneof=no occasionally yes"`
	Drinking *string `json:"drinking" validate:"omitempty,oneof=no occasionally yes"`
	AboutMe  *string `json:"about_me" validate:"omitempty,max=2000"`

	ProfileFor        *string  `json:"profile_for" validate:"omitempty,oneof=myself son daughter brother sister relative friend"`
	SubCommunity      *string  `json:"sub_community" validate:"omitempty,max=100"`
	CasteNoBar        *bool    `json:"caste_no_bar"`
	College           *string  `json:"college" validate:"omitempty,max=150"`
	WorkWith          *string  `json:"work_with" validate:"omitempty,oneof=private_company government defense business not_working"`
	CompanyName       *string  `json:"company_name" validate:"omitempty,max=150"`
	MatchmakingOptOut *bool    `json:"matchmaking_opt_out"`
	FamilyValues      *string  `json:"family_values" validate:"omitempty,oneof=traditional moderate liberal"`
	LivesWithFamily   *bool    `json:"lives_with_family"`
	Hobbies           []string `json:"hobbies" validate:"omitempty,max=30,dive,max=50"`
	Manglik           *string  `json:"manglik" validate:"omitempty,oneof=yes no dont_know"`
	Rashi             *string  `json:"rashi" validate:"omitempty,max=30"`
	Nakshatra         *string  `json:"nakshatra" validate:"omitempty,max=30"`
	BirthTime         *string  `json:"birth_time" validate:"omitempty,max=10"`
	BirthPlace        *string  `json:"birth_place" validate:"omitempty,max=150"`
	WeightKG          *int16   `json:"weight_kg" validate:"omitempty,gte=20,lte=300"`
	BodyType          *string  `json:"body_type" validate:"omitempty,oneof=slim athletic average heavy"`
	Complexion        *string  `json:"complexion" validate:"omitempty,max=30"`
	HasDisability     *bool    `json:"has_disability"`

	Visibility *string `json:"visibility" validate:"omitempty,oneof=public private"`
}

type ProfileResponse struct {
	ID     string `json:"id"`
	UserID string `json:"user_id"`

	FullName      *string `json:"full_name"`
	DateOfBirth   *string `json:"date_of_birth"`
	Gender        *string `json:"gender"`
	HeightCM      *int16  `json:"height_cm"`
	MaritalStatus *string `json:"marital_status"`

	Religion     *string `json:"religion"`
	Community    *string `json:"community"`
	MotherTongue *string `json:"mother_tongue"`

	Education       *string `json:"education"`
	Occupation      *string `json:"occupation"`
	AnnualIncomeINR *int64  `json:"annual_income_inr"`

	Country *string `json:"country"`
	State   *string `json:"state"`
	City    *string `json:"city"`

	FamilyType       *string `json:"family_type"`
	FamilyStatus     *string `json:"family_status"`
	FatherOccupation *string `json:"father_occupation"`
	MotherOccupation *string `json:"mother_occupation"`
	SiblingsCount    *int16  `json:"siblings_count"`

	Diet     *string `json:"diet"`
	Smoking  *string `json:"smoking"`
	Drinking *string `json:"drinking"`
	AboutMe  *string `json:"about_me"`

	ProfileFor        *string  `json:"profile_for"`
	SubCommunity      *string  `json:"sub_community"`
	CasteNoBar        *bool    `json:"caste_no_bar"`
	College           *string  `json:"college"`
	WorkWith          *string  `json:"work_with"`
	CompanyName       *string  `json:"company_name"`
	MatchmakingOptOut bool     `json:"matchmaking_opt_out"`
	FamilyValues      *string  `json:"family_values"`
	LivesWithFamily   *bool    `json:"lives_with_family"`
	Hobbies           []string `json:"hobbies"`
	SelfieVerified    bool     `json:"selfie_verified"`
	Manglik           *string  `json:"manglik"`
	Rashi             *string  `json:"rashi"`
	Nakshatra         *string  `json:"nakshatra"`
	BirthTime         *string  `json:"birth_time"`
	BirthPlace        *string  `json:"birth_place"`
	WeightKG          *int16   `json:"weight_kg"`
	BodyType          *string  `json:"body_type"`
	Complexion        *string  `json:"complexion"`
	HasDisability     *bool    `json:"has_disability"`

	Visibility        string          `json:"visibility"`
	ProfileCode       string          `json:"profile_code"`
	CompletionPercent int             `json:"completion_percent"`
	Photos            []PhotoResponse `json:"photos"`
	CreatedAt         string          `json:"created_at"`
}

type PhotoResponse struct {
	ID        string `json:"id"`
	URL       string `json:"url"`
	IsPrimary bool   `json:"is_primary"`
}

type ContactInfoResponse struct {
	Phone *string `json:"phone"`
	Email *string `json:"email"`
}
