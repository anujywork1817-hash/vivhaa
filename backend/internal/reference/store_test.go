package reference

import (
	"testing"
)

// The embedded files are generated, so these assert on the shape and on a
// handful of facts that would have to survive any regeneration — not on
// exact counts, which move whenever the upstream dataset refreshes.
func newStore(t *testing.T) *Store {
	t.Helper()
	s, err := New()
	if err != nil {
		t.Fatalf("New() failed — regenerate with scripts/gen_reference_data.py: %v", err)
	}
	return s
}

func TestNew_LoadsAllFourTables(t *testing.T) {
	s := newStore(t)

	if len(s.Countries()) < 200 {
		t.Errorf("got %d countries, expected the full world list", len(s.Countries()))
	}
	if len(s.Religions()) == 0 {
		t.Error("religions tree is empty")
	}
	if len(s.cities) == 0 {
		t.Error("cities table is empty — the gzip payload did not inflate")
	}
}

// The whole point of the change: picking the US must yield US states, not
// whatever list the screen happened to hardcode.
func TestStates_AreScopedToTheirCountry(t *testing.T) {
	s := newStore(t)

	for _, tc := range []struct {
		country  string
		minCount int
		want     string
		notWant  string
	}{
		{"US", 50, "Texas", "Maharashtra"},
		{"IN", 28, "Maharashtra", "Texas"},
		{"CA", 10, "Ontario", "Texas"},
		{"GB", 4, "Wales", "Maharashtra"},
		{"AU", 8, "Queensland", "Ontario"},
	} {
		t.Run(tc.country, func(t *testing.T) {
			states, ok := s.States(tc.country)
			if !ok {
				t.Fatalf("States(%q) reported an unknown country", tc.country)
			}
			if len(states) < tc.minCount {
				t.Errorf("got %d states, want at least %d", len(states), tc.minCount)
			}

			names := make(map[string]bool, len(states))
			for _, st := range states {
				names[st.Name] = true
			}
			if !names[tc.want] {
				t.Errorf("%q missing from %s states", tc.want, tc.country)
			}
			if names[tc.notWant] {
				t.Errorf("%q leaked into %s states", tc.notWant, tc.country)
			}
		})
	}
}

func TestStates_UnknownCountryIsDistinctFromNoStates(t *testing.T) {
	s := newStore(t)

	if _, ok := s.States("ZZ"); ok {
		t.Error("States(ZZ) should report an unknown country")
	}

	// Monaco is a real country the dataset gives no subdivisions for. That
	// must read as an empty list, not as a 404.
	states, ok := s.States("MC")
	if !ok {
		t.Fatal("States(MC) should report a known country")
	}
	if states == nil {
		t.Error("a known country with no subdivisions should return an empty slice, not nil")
	}
}

func TestStates_CodeLookupIsCaseInsensitive(t *testing.T) {
	s := newStore(t)

	upper, ok := s.States("US")
	if !ok {
		t.Fatal("States(US) failed")
	}
	lower, ok := s.States("us")
	if !ok {
		t.Fatal("States(us) failed — lookup should not be case sensitive")
	}
	if len(upper) != len(lower) {
		t.Errorf("US returned %d states but us returned %d", len(upper), len(lower))
	}
}

func TestCities_AreScopedToTheirState(t *testing.T) {
	s := newStore(t)

	texan, ok := s.Cities("US", "TX")
	if !ok {
		t.Fatal("Cities(US, TX) reported an unknown state")
	}
	if len(texan) == 0 {
		t.Fatal("Texas has no cities")
	}

	in := func(list []string, want string) bool {
		for _, v := range list {
			if v == want {
				return true
			}
		}
		return false
	}
	if !in(texan, "Houston") {
		t.Error("Houston missing from Texas")
	}
	if in(texan, "Mumbai") {
		t.Error("Mumbai leaked into Texas — the old hardcoded list is back")
	}

	maharashtra, ok := s.Cities("IN", "MH")
	if !ok {
		t.Fatal("Cities(IN, MH) reported an unknown state")
	}
	if !in(maharashtra, "Mumbai") {
		t.Error("Mumbai missing from Maharashtra")
	}
}

// A state code is only unique within its country, so the country must be
// part of the key. IN-MH and US-MH must not resolve to each other.
func TestCities_StateCodeIsScopedByCountry(t *testing.T) {
	s := newStore(t)

	if _, ok := s.Cities("US", "MH"); ok {
		t.Error("US has no state MH, but the lookup succeeded")
	}
	if _, ok := s.Cities("ZZ", "TX"); ok {
		t.Error("unknown country should not resolve a state")
	}
}

func TestSearchCities_PrefixMatchesRankFirst(t *testing.T) {
	s := newStore(t)

	got, ok := s.SearchCities("US", "CA", "san fran", 10)
	if !ok {
		t.Fatal("SearchCities(US, CA) reported an unknown state")
	}
	if len(got) == 0 {
		t.Fatal("no match for 'san fran' in California")
	}
	if got[0] != "San Francisco" {
		t.Errorf("first result = %q, want San Francisco", got[0])
	}
}

func TestSearchCities_RespectsLimit(t *testing.T) {
	s := newStore(t)

	got, ok := s.SearchCities("IN", "MH", "", 5)
	if !ok {
		t.Fatal("SearchCities(IN, MH) reported an unknown state")
	}
	if len(got) != 5 {
		t.Errorf("got %d cities, want the limit of 5", len(got))
	}

	// A limit of zero means "no cap" rather than "no results".
	all, _ := s.SearchCities("IN", "MH", "", 0)
	if len(all) <= 5 {
		t.Errorf("unlimited search returned %d cities, expected the full list", len(all))
	}
}

func TestSearchCities_NoMatchIsEmptyNotNil(t *testing.T) {
	s := newStore(t)

	got, ok := s.SearchCities("US", "TX", "zzzzznotacity", 10)
	if !ok {
		t.Fatal("SearchCities reported an unknown state")
	}
	if got == nil {
		t.Error("no-match should return an empty slice so it encodes as [] not null")
	}
	if len(got) != 0 {
		t.Errorf("got %d results for a nonsense query", len(got))
	}
}

func TestReligions_TreeIsWellFormed(t *testing.T) {
	s := newStore(t)

	seen := map[string]bool{}
	for _, r := range s.Religions() {
		if r.Name == "" {
			t.Error("religion with an empty name")
		}
		if seen[r.Name] {
			t.Errorf("duplicate religion %q", r.Name)
		}
		seen[r.Name] = true

		if len(r.Communities) == 0 {
			t.Errorf("religion %q has no communities", r.Name)
		}
		for _, c := range r.Communities {
			if c.Name == "" {
				t.Errorf("religion %q has a community with an empty name", r.Name)
			}
			// SubCastes may legitimately be empty, but must never be nil —
			// that would serialise as null and break the client's list decode.
			if c.SubCastes == nil {
				t.Errorf("%s / %s has nil sub_castes; want []", r.Name, c.Name)
			}
		}
	}

	for _, want := range []string{"Hindu", "Muslim", "Christian", "Sikh", "Jain"} {
		if !seen[want] {
			t.Errorf("%q missing from the religion list", want)
		}
	}
}

func TestReligions_CommunitiesAreScopedToTheirReligion(t *testing.T) {
	s := newStore(t)

	communities := func(religion string) map[string]bool {
		for _, r := range s.Religions() {
			if r.Name == religion {
				out := map[string]bool{}
				for _, c := range r.Communities {
					out[c.Name] = true
				}
				return out
			}
		}
		t.Fatalf("religion %q not found", religion)
		return nil
	}

	hindu := communities("Hindu")
	if !hindu["Brahmin"] {
		t.Error("Brahmin missing from Hindu communities")
	}
	if hindu["Sunni"] {
		t.Error("Sunni should not appear under Hindu")
	}

	muslim := communities("Muslim")
	if !muslim["Sunni"] {
		t.Error("Sunni missing from Muslim communities")
	}
	if muslim["Brahmin"] {
		t.Error("Brahmin should not appear under Muslim")
	}
}
