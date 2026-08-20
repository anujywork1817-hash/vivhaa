package reference

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

// Routes are exercised without the auth middleware — RequireAuth is covered
// by its own tests, and mounting it here would only prove that a fake token
// parses. What matters is the path shape and the response envelope.
func newTestRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)

	store, err := New()
	if err != nil {
		t.Fatalf("New() failed: %v", err)
	}
	h := NewHandler(store)

	r := gin.New()
	r.GET("/reference/countries", h.ListCountries)
	r.GET("/reference/countries/:country/states", h.ListStates)
	r.GET("/reference/countries/:country/states/:state/cities", h.ListCities)
	r.GET("/reference/religions", h.ListReligions)
	return r
}

// get issues a request and decodes the standard {success, data} envelope,
// asserting the status along the way.
func get(t *testing.T, r *gin.Engine, path string, wantStatus int) json.RawMessage {
	t.Helper()

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))

	if w.Code != wantStatus {
		t.Fatalf("GET %s = %d, want %d (body: %s)", path, w.Code, wantStatus, w.Body)
	}

	var env struct {
		Success bool            `json:"success"`
		Data    json.RawMessage `json:"data"`
		Error   *struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &env); err != nil {
		t.Fatalf("GET %s returned undecodable body: %v", path, err)
	}

	if wantStatus == http.StatusOK {
		if !env.Success {
			t.Fatalf("GET %s: success=false on a 200", path)
		}
		return env.Data
	}
	if env.Success {
		t.Fatalf("GET %s: success=true on a %d", path, wantStatus)
	}
	return nil
}

func TestListCountries(t *testing.T) {
	r := newTestRouter(t)

	var got []Country
	if err := json.Unmarshal(get(t, r, "/reference/countries", http.StatusOK), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if len(got) < 200 {
		t.Errorf("got %d countries, want the full list", len(got))
	}
	// Sorted by name, so the first entry should be near the top of the
	// alphabet rather than whatever order the source file happened to use.
	if len(got) > 1 && got[0].Name > got[1].Name {
		t.Errorf("countries are not sorted by name: %q before %q", got[0].Name, got[1].Name)
	}
	for _, c := range got {
		if c.Code == "" || c.Name == "" {
			t.Fatalf("country with a missing field: %+v", c)
		}
	}
}

func TestListStates_ForTheRequestedCountry(t *testing.T) {
	r := newTestRouter(t)

	var got []State
	raw := get(t, r, "/reference/countries/US/states", http.StatusOK)
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}

	names := map[string]bool{}
	for _, s := range got {
		names[s.Name] = true
	}
	if !names["California"] {
		t.Error("California missing from US states")
	}
	if names["Maharashtra"] {
		t.Error("Maharashtra served under US — the lists are not scoped")
	}
}

func TestListStates_UnknownCountryIs404(t *testing.T) {
	r := newTestRouter(t)
	get(t, r, "/reference/countries/ZZ/states", http.StatusNotFound)
}

func TestListCities_ScopedToStateAndCapped(t *testing.T) {
	r := newTestRouter(t)

	var got []string
	if err := json.Unmarshal(
		get(t, r, "/reference/countries/IN/states/MH/cities", http.StatusOK), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if len(got) == 0 {
		t.Fatal("Maharashtra returned no cities")
	}
	if len(got) > defaultCityLimit {
		t.Errorf("got %d cities, want the default cap of %d", len(got), defaultCityLimit)
	}
}

func TestListCities_SearchNarrowsResults(t *testing.T) {
	r := newTestRouter(t)

	var got []string
	if err := json.Unmarshal(
		get(t, r, "/reference/countries/IN/states/MH/cities?q=mumbai", http.StatusOK),
		&got); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if len(got) == 0 {
		t.Fatal("no match for 'mumbai' in Maharashtra")
	}
	for _, city := range got {
		if !containsFold(city, "mumbai") {
			t.Errorf("%q does not match the query", city)
		}
	}
}

func TestListCities_UnknownStateIs404(t *testing.T) {
	r := newTestRouter(t)

	// TX is a real state code, but not in India.
	get(t, r, "/reference/countries/IN/states/TX/cities", http.StatusNotFound)
	get(t, r, "/reference/countries/ZZ/states/TX/cities", http.StatusNotFound)
}

func TestListCities_RejectsABadLimit(t *testing.T) {
	r := newTestRouter(t)

	get(t, r, "/reference/countries/IN/states/MH/cities?limit=abc", http.StatusBadRequest)
	get(t, r, "/reference/countries/IN/states/MH/cities?limit=0", http.StatusBadRequest)
	get(t, r, "/reference/countries/IN/states/MH/cities?limit=-5", http.StatusBadRequest)

	// Over the ceiling is clamped, not rejected.
	var got []string
	if err := json.Unmarshal(
		get(t, r, "/reference/countries/IN/states/MH/cities?limit=99999", http.StatusOK),
		&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got) > maxCityLimit {
		t.Errorf("got %d cities, want no more than the %d ceiling", len(got), maxCityLimit)
	}
}

func TestListReligions_ServesTheWholeTree(t *testing.T) {
	r := newTestRouter(t)

	var got []Religion
	if err := json.Unmarshal(
		get(t, r, "/reference/religions", http.StatusOK), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}

	if len(got) == 0 {
		t.Fatal("no religions served")
	}
	for _, religion := range got {
		for _, c := range religion.Communities {
			// An omitempty or nil slice here would decode as null on the
			// client and break its List<String> cast.
			if c.SubCastes == nil {
				t.Errorf("%s / %s serialised sub_castes as null", religion.Name, c.Name)
			}
		}
	}
}

func containsFold(haystack, needle string) bool {
	h, n := []rune(haystack), []rune(needle)
	lower := func(r rune) rune {
		if r >= 'A' && r <= 'Z' {
			return r + 32
		}
		return r
	}
	if len(n) > len(h) {
		return false
	}
	for i := 0; i+len(n) <= len(h); i++ {
		match := true
		for j := range n {
			if lower(h[i+j]) != lower(n[j]) {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}
