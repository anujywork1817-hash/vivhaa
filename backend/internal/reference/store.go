// Package reference serves the fixed lookup lists the apps use to populate
// their pickers — countries, states, cities, and the religion/community/
// sub-caste tree.
//
// These lived as hardcoded Dart constants in the mobile app, which meant a
// member in Texas was offered a list of Maharashtra cities and any change
// needed an app-store release. Serving them here makes the pickers cascade
// off real data and lets the lists change with a backend deploy.
package reference

import (
	"bytes"
	"compress/gzip"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"strings"
)

//go:embed data/countries.json
var countriesJSON []byte

//go:embed data/states.json
var statesJSON []byte

// Cities are ~2 MB as plain JSON and ~780 KB packed, so they ship gzipped
// and are inflated once at startup rather than bloating the binary.
//
//go:embed data/cities.json.gz
var citiesGZ []byte

//go:embed data/religions.json
var religionsJSON []byte

// Country is one entry in the country picker.
type Country struct {
	Code  string `json:"code"`
	Name  string `json:"name"`
	Emoji string `json:"emoji"`
}

// State is a first-level subdivision — a US state, an Indian state, a
// Canadian province. Code is unique within its country, not globally.
type State struct {
	Code string `json:"code"`
	Name string `json:"name"`
}

// Community is one community within a religion, with its sub-castes.
type Community struct {
	Name      string   `json:"name"`
	SubCastes []string `json:"sub_castes"`
}

// Religion is the root of the community/sub-caste tree.
type Religion struct {
	Name        string      `json:"name"`
	Communities []Community `json:"communities"`
}

// Store holds the decoded lookup tables. It is read-only after New and
// therefore safe to share across requests without locking.
type Store struct {
	countries []Country
	states    map[string][]State
	cities    map[string]map[string][]string
	religions []Religion
}

// New decodes the embedded data. It returns an error rather than panicking
// so a corrupt regeneration fails the process start with a clear message
// instead of surfacing as empty pickers at runtime.
func New() (*Store, error) {
	s := &Store{}

	if err := json.Unmarshal(countriesJSON, &s.countries); err != nil {
		return nil, fmt.Errorf("decode countries: %w", err)
	}
	if err := json.Unmarshal(statesJSON, &s.states); err != nil {
		return nil, fmt.Errorf("decode states: %w", err)
	}
	if err := json.Unmarshal(religionsJSON, &s.religions); err != nil {
		return nil, fmt.Errorf("decode religions: %w", err)
	}

	zr, err := gzip.NewReader(bytes.NewReader(citiesGZ))
	if err != nil {
		return nil, fmt.Errorf("open cities archive: %w", err)
	}
	defer zr.Close()
	raw, err := io.ReadAll(zr)
	if err != nil {
		return nil, fmt.Errorf("inflate cities: %w", err)
	}
	if err := json.Unmarshal(raw, &s.cities); err != nil {
		return nil, fmt.Errorf("decode cities: %w", err)
	}

	if len(s.countries) == 0 || len(s.states) == 0 || len(s.religions) == 0 {
		return nil, fmt.Errorf("reference data is empty — regenerate with scripts/gen_reference_data.py")
	}
	return s, nil
}

// Countries returns every country, ordered by name.
func (s *Store) Countries() []Country { return s.countries }

// States returns the subdivisions of a country. The bool reports whether the
// country code is known at all, which is what separates "no such country"
// (404) from a country that genuinely has no subdivisions (empty 200) —
// Monaco and Vatican City are the real cases.
func (s *Store) States(country string) ([]State, bool) {
	if !s.hasCountry(country) {
		return nil, false
	}
	states, ok := s.states[normalise(country)]
	if !ok {
		return []State{}, true
	}
	return states, true
}

// Cities returns the cities of one state, ordered by name. As with States,
// the bool distinguishes an unknown country/state from a known one that has
// no city records.
func (s *Store) Cities(country, state string) ([]string, bool) {
	states, ok := s.States(country)
	if !ok {
		return nil, false
	}
	stateCode := normalise(state)
	known := false
	for _, st := range states {
		if normalise(st.Code) == stateCode {
			known = true
			break
		}
	}
	if !known {
		return nil, false
	}
	byState, ok := s.cities[normalise(country)]
	if !ok {
		return []string{}, true
	}
	cities, ok := byState[stateCode]
	if !ok {
		return []string{}, true
	}
	return cities, true
}

// Religions returns the whole religion -> community -> sub-caste tree. It is
// only a few KB, so the apps fetch it once and cascade locally rather than
// making a round trip per level.
func (s *Store) Religions() []Religion { return s.religions }

func (s *Store) hasCountry(code string) bool {
	code = normalise(code)
	// The list is sorted by name, not code, so this is a linear scan over
	// 250 entries — cheap enough not to warrant a second index.
	for _, c := range s.countries {
		if normalise(c.Code) == code {
			return true
		}
	}
	return false
}

// normalise upper-cases and trims a path code so `/countries/in/states` and
// `/countries/IN/states` resolve alike.
func normalise(code string) string {
	return strings.ToUpper(strings.TrimSpace(code))
}

// SearchCities filters a state's cities by a case-insensitive prefix, then
// substring, match. Some Indian states carry over a thousand cities, which
// is more than a picker should render at once.
func (s *Store) SearchCities(country, state, query string, limit int) ([]string, bool) {
	cities, ok := s.Cities(country, state)
	if !ok {
		return nil, false
	}
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" {
		if limit > 0 && len(cities) > limit {
			return cities[:limit], true
		}
		return cities, true
	}

	var prefix, contains []string
	for _, city := range cities {
		lower := strings.ToLower(city)
		switch {
		case strings.HasPrefix(lower, query):
			prefix = append(prefix, city)
		case strings.Contains(lower, query):
			contains = append(contains, city)
		}
	}
	// Prefix hits first — someone typing "san" wants San Diego above
	// Ciudad Sandino — with each group left in the store's name order.
	sort.SliceStable(contains, func(i, j int) bool { return contains[i] < contains[j] })
	out := append(prefix, contains...)
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	if out == nil {
		out = []string{}
	}
	return out, true
}
