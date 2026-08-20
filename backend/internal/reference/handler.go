package reference

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/response"
)

// defaultCityLimit caps an unfiltered city listing. West Bengal alone has
// over a thousand entries, and a picker that renders them all is slower to
// scroll than it is to type into.
const defaultCityLimit = 200

// maxCityLimit is the ceiling a caller can ask for.
const maxCityLimit = 1000

// Handler exposes the reference lists over HTTP.
type Handler struct {
	store *Store
}

// NewHandler wires a handler to a loaded store.
func NewHandler(store *Store) *Handler {
	return &Handler{store: store}
}

// ListCountries handles GET /reference/countries.
func (h *Handler) ListCountries(c *gin.Context) {
	response.OK(c, h.store.Countries())
}

// ListStates handles GET /reference/countries/:country/states.
func (h *Handler) ListStates(c *gin.Context) {
	states, ok := h.store.States(c.Param("country"))
	if !ok {
		response.Fail(c, http.StatusNotFound, "unknown_country",
			"no country with that code", nil)
		return
	}
	response.OK(c, states)
}

// ListCities handles GET /reference/countries/:country/states/:state/cities.
// An optional `q` filters by name and `limit` caps the result.
func (h *Handler) ListCities(c *gin.Context) {
	limit := defaultCityLimit
	if raw := c.Query("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			response.Fail(c, http.StatusBadRequest, "invalid_limit",
				"limit must be a positive integer", nil)
			return
		}
		if parsed > maxCityLimit {
			parsed = maxCityLimit
		}
		limit = parsed
	}

	cities, ok := h.store.SearchCities(
		c.Param("country"), c.Param("state"), c.Query("q"), limit)
	if !ok {
		response.Fail(c, http.StatusNotFound, "unknown_state",
			"no state with that code in that country", nil)
		return
	}
	response.OK(c, cities)
}

// ListReligions handles GET /reference/religions, returning the full
// religion -> community -> sub-caste tree in one response.
func (h *Handler) ListReligions(c *gin.Context) {
	response.OK(c, h.store.Religions())
}
