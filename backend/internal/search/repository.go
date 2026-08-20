package search

import (
	"context"
	"encoding/json"
	"time"

	"matrimony-backend/pkg/elasticsearch"
)

type Repository struct {
	es        *elasticsearch.Client
	indexName string
}

func NewRepository(es *elasticsearch.Client, indexName string) *Repository {
	return &Repository{es: es, indexName: indexName}
}

// Search runs a filtered, paginated query over public profiles in
// Elasticsearch, excluding the requesting user's own profile and anyone
// blocked in either direction.
func (r *Repository) Search(ctx context.Context, excludeUserIDs []string, q Query) ([]ProfileResult, int, error) {
	filters := []map[string]any{
		{"term": map[string]any{"visibility": "public"}},
	}
	mustNot := []map[string]any{
		{"terms": map[string]any{"user_id": excludeUserIDs}},
		// BUG-H07: matchmaking_opt_out was persisted and indexed but never
		// filtered on — an opted-out profile must not appear in search.
		{"term": map[string]any{"matchmaking_opt_out": true}},
	}

	if q.Gender != nil {
		filters = append(filters, map[string]any{"term": map[string]any{"gender": *q.Gender}})
	}
	if len(q.MaritalStatus) > 0 {
		filters = append(filters, map[string]any{"terms": map[string]any{"marital_status": q.MaritalStatus}})
	}
	if len(q.Religion) > 0 {
		filters = append(filters, map[string]any{"bool": map[string]any{"should": matchAny("religion", q.Religion)}})
	}
	if len(q.Community) > 0 {
		filters = append(filters, map[string]any{"bool": map[string]any{"should": matchAny("community", q.Community)}})
	}
	if len(q.Education) > 0 {
		filters = append(filters, map[string]any{"bool": map[string]any{"should": matchAny("education", q.Education)}})
	}
	if len(q.Occupation) > 0 {
		filters = append(filters, map[string]any{"bool": map[string]any{"should": matchAny("occupation", q.Occupation)}})
	}
	if q.City != nil {
		filters = append(filters, map[string]any{"match": map[string]any{"city": *q.City}})
	}
	if q.State != nil {
		filters = append(filters, map[string]any{"match": map[string]any{"state": *q.State}})
	}
	if len(q.Diet) > 0 {
		filters = append(filters, map[string]any{"terms": map[string]any{"diet": q.Diet}})
	}
	if q.Manglik != nil {
		filters = append(filters, map[string]any{"term": map[string]any{"manglik": *q.Manglik}})
	}
	if q.MinHeightCM != nil || q.MaxHeightCM != nil {
		heightRange := map[string]any{}
		if q.MinHeightCM != nil {
			heightRange["gte"] = *q.MinHeightCM
		}
		if q.MaxHeightCM != nil {
			heightRange["lte"] = *q.MaxHeightCM
		}
		filters = append(filters, map[string]any{"range": map[string]any{"height_cm": heightRange}})
	}
	if q.Query != nil && *q.Query != "" {
		filters = append(filters, map[string]any{
			"multi_match": map[string]any{
				"query":  *q.Query,
				"fields": []string{"full_name", "occupation", "city"},
			},
		})
	}

	if q.MinAge != nil || q.MaxAge != nil {
		dobRange := map[string]any{}
		now := time.Now()
		// older age => earlier (smaller) date_of_birth
		if q.MaxAge != nil {
			dobRange["gte"] = now.AddDate(-(*q.MaxAge)-1, 0, 1).Format("2006-01-02")
		}
		if q.MinAge != nil {
			dobRange["lte"] = now.AddDate(-*q.MinAge, 0, 0).Format("2006-01-02")
		}
		filters = append(filters, map[string]any{"range": map[string]any{"date_of_birth": dobRange}})
	}

	if q.MinIncomeINR != nil || q.MaxIncomeINR != nil {
		incomeRange := map[string]any{}
		if q.MinIncomeINR != nil {
			incomeRange["gte"] = *q.MinIncomeINR
		}
		if q.MaxIncomeINR != nil {
			incomeRange["lte"] = *q.MaxIncomeINR
		}
		filters = append(filters, map[string]any{"range": map[string]any{"annual_income_inr": incomeRange}})
	}

	query := map[string]any{
		"from": (q.Page - 1) * q.Limit,
		"size": q.Limit,
		"sort": []map[string]any{{"created_at": map[string]any{"order": "desc"}}},
		"query": map[string]any{
			"bool": map[string]any{
				"filter":   filters,
				"must_not": mustNot,
			},
		},
	}

	result, err := r.es.Search(ctx, r.indexName, query)
	if elasticsearch.IsNotFoundIndexError(err) {
		return []ProfileResult{}, 0, nil
	}
	if err != nil {
		return nil, 0, err
	}

	results := make([]ProfileResult, 0, len(result.Hits))
	for _, raw := range result.Hits {
		var doc ProfileDocument
		if err := json.Unmarshal(raw, &doc); err != nil {
			return nil, 0, err
		}
		results = append(results, ProfileResult{
			ProfileID:     doc.ProfileID,
			ProfileCode:   doc.ProfileCode,
			FullName:      doc.FullName,
			Age:           ageFromDOB(doc.DateOfBirth),
			Gender:        doc.Gender,
			Religion:      doc.Religion,
			Community:     doc.Community,
			Education:     doc.Education,
			Occupation:    doc.Occupation,
			City:          doc.City,
			State:         doc.State,
			PhotoURL:      doc.PhotoURL,
			HeightCM:      doc.HeightCM,
			MaritalStatus: doc.MaritalStatus,
			Diet:          doc.Diet,
			Manglik:       doc.Manglik,
		})
	}

	return results, result.Total, nil
}

// matchAny builds an OR of "match" clauses for a text field against a list
// of candidate values — text fields can't use "terms" (that's exact-match
// only, for keyword fields), so this is the multi-select equivalent.
func matchAny(field string, values []string) []map[string]any {
	clauses := make([]map[string]any, 0, len(values))
	for _, v := range values {
		clauses = append(clauses, map[string]any{"match": map[string]any{field: v}})
	}
	return clauses
}

func ageFromDOB(dob *string) *int {
	if dob == nil {
		return nil
	}
	t, err := time.Parse("2006-01-02", *dob)
	if err != nil {
		return nil
	}
	years := int(time.Since(t).Hours() / 24 / 365.25)
	return &years
}
