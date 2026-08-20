package matchmaking

import (
	"strings"
	"time"

	"matrimony-backend/internal/preferences"
)

// weight of each criterion when the corresponding preference is set.
// Criteria whose preference is left empty are skipped entirely rather
// than counted as a miss, so an incomplete preferences form never
// artificially tanks every candidate's score.
const (
	weightAge           = 20
	weightReligion      = 20
	weightCommunity     = 15
	weightCity          = 15
	weightDiet          = 10
	weightMaritalStatus = 10
	weightIncome        = 10
)

// Score returns a 0-100 compatibility score between the caller's
// preferences and a candidate profile. hasPreferences is false when the
// caller hasn't saved preferences yet, in which case every candidate
// scores a neutral 50.
func Score(pref preferences.Preferences, hasPreferences bool, c Candidate) int {
	if !hasPreferences {
		return 50
	}

	applicable := 0
	matched := 0

	if pref.MinAge != nil || pref.MaxAge != nil {
		applicable += weightAge
		if age := ageFromDOB(c.DateOfBirth); age != nil {
			ok := true
			if pref.MinAge != nil && *age < int(*pref.MinAge) {
				ok = false
			}
			if pref.MaxAge != nil && *age > int(*pref.MaxAge) {
				ok = false
			}
			if ok {
				matched += weightAge
			}
		}
	}

	if len(pref.Religion) > 0 {
		applicable += weightReligion
		if c.Religion != nil && containsFold(pref.Religion, *c.Religion) {
			matched += weightReligion
		}
	}

	if len(pref.Community) > 0 {
		applicable += weightCommunity
		if c.Community != nil && containsFold(pref.Community, *c.Community) {
			matched += weightCommunity
		}
	}

	if len(pref.City) > 0 {
		applicable += weightCity
		if c.City != nil && containsFold(pref.City, *c.City) {
			matched += weightCity
		}
	}

	if len(pref.Diet) > 0 {
		applicable += weightDiet
		if c.Diet != nil && containsFold(pref.Diet, *c.Diet) {
			matched += weightDiet
		}
	}

	if len(pref.MaritalStatus) > 0 {
		applicable += weightMaritalStatus
		if c.MaritalStatus != nil && containsFold(pref.MaritalStatus, *c.MaritalStatus) {
			matched += weightMaritalStatus
		}
	}

	if pref.MinIncomeINR != nil {
		applicable += weightIncome
		if c.AnnualIncomeINR != nil && *c.AnnualIncomeINR >= *pref.MinIncomeINR {
			matched += weightIncome
		}
	}

	if applicable == 0 {
		return 50
	}
	return matched * 100 / applicable
}

func ageFromDOB(dob *time.Time) *int {
	if dob == nil {
		return nil
	}
	years := time.Since(*dob).Hours() / 24 / 365.25
	age := int(years)
	return &age
}

func containsFold(list []string, target string) bool {
	for _, v := range list {
		if strings.EqualFold(v, target) {
			return true
		}
	}
	return false
}
