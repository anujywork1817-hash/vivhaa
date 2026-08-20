package search

// ProfileDocument is the shape indexed into Elasticsearch for one profile.
// cmd/worker builds and writes these; this package only reads them back.
type ProfileDocument struct {
	ProfileID       string  `json:"profile_id"`
	ProfileCode     string  `json:"profile_code"`
	UserID          string  `json:"user_id"`
	FullName        *string `json:"full_name"`
	DateOfBirth     *string `json:"date_of_birth,omitempty"` // YYYY-MM-DD
	Gender          *string `json:"gender"`
	MaritalStatus   *string `json:"marital_status"`
	Religion        *string `json:"religion"`
	Community       *string `json:"community"`
	Education       *string `json:"education"`
	Occupation      *string `json:"occupation"`
	City            *string `json:"city"`
	State           *string `json:"state"`
	AnnualIncomeINR *int64  `json:"annual_income_inr"`
	Diet            *string `json:"diet"`
	Visibility      string  `json:"visibility"`
	PhotoURL        *string `json:"photo_url"`
	CreatedAt       string  `json:"created_at"`
	HeightCM        *int16  `json:"height_cm,omitempty"`
	Manglik         *string `json:"manglik,omitempty"`
	// MatchmakingOptOut mirrors profiles.matchmaking_opt_out (BUG-H07) — an
	// opted-out profile must never appear in search results, same as it
	// must never appear in CandidatePool/NearbyCandidates.
	MatchmakingOptOut bool `json:"matchmaking_opt_out"`
}

// IndexMapping is the Elasticsearch index creation body: keyword fields
// for exact/case-insensitive-ish filtering (via the standard analyzer's
// lowercasing on the matching "text" fields below), a date field for
// age-range queries, and a long for income-range queries.
const IndexMapping = `{
  "mappings": {
    "properties": {
      "profile_id":        { "type": "keyword" },
      "profile_code":      { "type": "keyword" },
      "user_id":           { "type": "keyword" },
      "full_name":         { "type": "text" },
      "date_of_birth":     { "type": "date", "format": "yyyy-MM-dd" },
      "gender":            { "type": "keyword" },
      "marital_status":    { "type": "keyword" },
      "religion":          { "type": "text" },
      "community":         { "type": "text" },
      "education":         { "type": "text" },
      "occupation":        { "type": "text" },
      "city":              { "type": "text" },
      "state":             { "type": "text" },
      "annual_income_inr": { "type": "long" },
      "diet":              { "type": "keyword" },
      "visibility":        { "type": "keyword" },
      "photo_url":         { "type": "keyword" },
      "created_at":        { "type": "date" },
      "height_cm":         { "type": "short" },
      "manglik":           { "type": "keyword" },
      "matchmaking_opt_out": { "type": "boolean" }
    }
  }
}`
