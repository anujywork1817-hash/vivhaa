package matchmaking

import (
	"testing"
	"time"

	"matrimony-backend/internal/preferences"
)

func strp(s string) *string { return &s }

// bornYearsAgo builds a date of birth for someone of roughly the given
// age, offset a few months in so the result isn't sitting exactly on a
// year boundary where rounding could flip it.
func bornYearsAgo(years int) *time.Time {
	t := time.Now().AddDate(-years, -3, 0)
	return &t
}

func TestScore_NeutralWhenNoPreferencesSaved(t *testing.T) {
	candidate := Candidate{Religion: strp("Hindu"), City: strp("Pune")}

	if got := Score(preferences.Preferences{}, false, candidate); got != 50 {
		t.Fatalf("Score without saved preferences = %d, want 50", got)
	}
}

// Preferences saved but every field left blank means nothing to match on,
// which is the same "no signal" case as having no preferences at all.
func TestScore_NeutralWhenPreferencesAreEmpty(t *testing.T) {
	candidate := Candidate{Religion: strp("Hindu")}

	if got := Score(preferences.Preferences{}, true, candidate); got != 50 {
		t.Fatalf("Score with empty preferences = %d, want 50", got)
	}
}

func TestScore_PerfectAndZeroMatch(t *testing.T) {
	income := int64(1000000)
	minAge, maxAge := int16(25), int16(32)

	pref := preferences.Preferences{
		MinAge:        &minAge,
		MaxAge:        &maxAge,
		Religion:      []string{"Hindu"},
		Community:     []string{"Maratha"},
		City:          []string{"Pune"},
		Diet:          []string{"vegetarian"},
		MaritalStatus: []string{"never_married"},
		MinIncomeINR:  &income,
	}

	candidateIncome := int64(1500000)
	perfect := Candidate{
		DateOfBirth:     bornYearsAgo(28),
		Religion:        strp("Hindu"),
		Community:       strp("Maratha"),
		City:            strp("Pune"),
		Diet:            strp("vegetarian"),
		MaritalStatus:   strp("never_married"),
		AnnualIncomeINR: &candidateIncome,
	}
	if got := Score(pref, true, perfect); got != 100 {
		t.Errorf("perfect candidate scored %d, want 100", got)
	}

	lowIncome := int64(100000)
	none := Candidate{
		DateOfBirth:     bornYearsAgo(45),
		Religion:        strp("Christian"),
		Community:       strp("Other"),
		City:            strp("Chennai"),
		Diet:            strp("non_vegetarian"),
		MaritalStatus:   strp("divorced"),
		AnnualIncomeINR: &lowIncome,
	}
	if got := Score(pref, true, none); got != 0 {
		t.Errorf("non-matching candidate scored %d, want 0", got)
	}
}

// Criteria the user left blank must be skipped, not counted as misses —
// otherwise a half-filled preferences form would drag every score down.
func TestScore_UnsetCriteriaAreSkippedNotPenalised(t *testing.T) {
	// Only religion is expressed, and the candidate matches it.
	pref := preferences.Preferences{Religion: []string{"Hindu"}}
	candidate := Candidate{
		Religion: strp("Hindu"),
		// Everything else deliberately mismatched/absent.
		City:          strp("Chennai"),
		Diet:          strp("non_vegetarian"),
		MaritalStatus: strp("divorced"),
	}

	if got := Score(pref, true, candidate); got != 100 {
		t.Fatalf("score = %d, want 100 — unset criteria should not count against a candidate", got)
	}
}

func TestScore_IsCaseInsensitive(t *testing.T) {
	pref := preferences.Preferences{
		Religion: []string{"hindu"},
		City:     []string{"PUNE"},
	}
	candidate := Candidate{Religion: strp("Hindu"), City: strp("pune")}

	if got := Score(pref, true, candidate); got != 100 {
		t.Fatalf("score = %d, want 100 — matching should ignore case", got)
	}
}

// A candidate missing the field a preference asks about can't match it,
// but must not blow up either. The criteria are weighted rather than equal
// (religion 20, city 15), so a religion-only match is scored against the
// combined weight of both expressed criteria.
func TestScore_MissingCandidateFieldsCountAsMiss(t *testing.T) {
	pref := preferences.Preferences{
		Religion: []string{"Hindu"},
		City:     []string{"Pune"},
	}

	// Religion matches, city is unknown on the candidate.
	candidate := Candidate{Religion: strp("Hindu")}

	want := weightReligion * 100 / (weightReligion + weightCity)
	if got := Score(pref, true, candidate); got != want {
		t.Fatalf("score = %d, want %d (religion matched, city missing)", got, want)
	}
}

// The weights are a product decision, not an implementation detail — a
// change here silently reorders everyone's matches, so they're pinned.
func TestScore_CriteriaWeightings(t *testing.T) {
	weights := map[string]int{
		"age":            weightAge,
		"religion":       weightReligion,
		"community":      weightCommunity,
		"city":           weightCity,
		"diet":           weightDiet,
		"marital status": weightMaritalStatus,
		"income":         weightIncome,
	}
	expected := map[string]int{
		"age": 20, "religion": 20, "community": 15,
		"city": 15, "diet": 10, "marital status": 10, "income": 10,
	}

	total := 0
	for name, got := range weights {
		if got != expected[name] {
			t.Errorf("%s weight = %d, want %d", name, got, expected[name])
		}
		total += got
	}
	if total != 100 {
		t.Errorf("weights sum to %d, want 100 so a full match scores exactly 100", total)
	}
}

func TestScore_AgeRangeBoundaries(t *testing.T) {
	minAge, maxAge := int16(25), int16(30)
	pref := preferences.Preferences{MinAge: &minAge, MaxAge: &maxAge}

	tests := []struct {
		name      string
		age       int
		wantMatch bool
	}{
		{name: "below range", age: 22},
		{name: "at lower bound", age: 25, wantMatch: true},
		{name: "inside range", age: 28, wantMatch: true},
		{name: "at upper bound", age: 30, wantMatch: true},
		{name: "above range", age: 34},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Score(pref, true, Candidate{DateOfBirth: bornYearsAgo(tt.age)})
			want := 0
			if tt.wantMatch {
				want = 100
			}
			if got != want {
				t.Fatalf("age %d scored %d, want %d", tt.age, got, want)
			}
		})
	}
}

func TestScore_IncomeIsAMinimumNotAnExactMatch(t *testing.T) {
	minIncome := int64(1000000)
	pref := preferences.Preferences{MinIncomeINR: &minIncome}

	above := int64(5000000)
	exact := int64(1000000)
	below := int64(999999)

	if got := Score(pref, true, Candidate{AnnualIncomeINR: &above}); got != 100 {
		t.Errorf("income above the minimum scored %d, want 100", got)
	}
	if got := Score(pref, true, Candidate{AnnualIncomeINR: &exact}); got != 100 {
		t.Errorf("income exactly at the minimum scored %d, want 100", got)
	}
	if got := Score(pref, true, Candidate{AnnualIncomeINR: &below}); got != 0 {
		t.Errorf("income below the minimum scored %d, want 0", got)
	}
}

// Whatever the inputs, the score is a percentage and must stay in range —
// it's surfaced directly to users as a compatibility figure.
func TestScore_AlwaysWithinRange(t *testing.T) {
	minAge, maxAge := int16(25), int16(30)
	income := int64(500000)
	pref := preferences.Preferences{
		MinAge:        &minAge,
		MaxAge:        &maxAge,
		Religion:      []string{"Hindu", "Jain"},
		Community:     []string{"Maratha"},
		City:          []string{"Pune", "Mumbai"},
		Diet:          []string{"vegetarian"},
		MaritalStatus: []string{"never_married"},
		MinIncomeINR:  &income,
	}

	candidates := []Candidate{
		{},
		{DateOfBirth: bornYearsAgo(28)},
		{Religion: strp("Jain"), City: strp("Mumbai")},
		{DateOfBirth: bornYearsAgo(99), Religion: strp("")},
	}

	for i, c := range candidates {
		got := Score(pref, true, c)
		if got < 0 || got > 100 {
			t.Errorf("candidate %d scored %d, outside 0-100", i, got)
		}
	}
}
