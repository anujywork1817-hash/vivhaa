// cmd/reindex is a one-off operational tool: it (re)builds the
// Elasticsearch index from every profile row currently in Postgres.
//
// Needed after anything that leaves the DB and the ES index out of sync
// without either side ever publishing a profile.updated event to tell
// cmd/worker to catch up — the main case being a database restore/migration
// onto a fresh Elasticsearch (search/matches would otherwise stay empty
// until each profile happens to be edited again). Safe to run any time:
// it's a full overwrite of each document, not additive, so running it
// twice or against an already-consistent index is a harmless no-op.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"matrimony-backend/configs"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/search"
	"matrimony-backend/pkg/database"
	"matrimony-backend/pkg/elasticsearch"
	"matrimony-backend/pkg/logger"
)

func main() {
	cfg, err := configs.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "fatal: invalid configuration:", err)
		os.Exit(1)
	}

	log := logger.New(cfg.Env)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	dbPool, err := database.NewPool(ctx, cfg.DB)
	if err != nil {
		log.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer dbPool.Close()

	esClient, err := elasticsearch.NewClient(cfg.ES)
	if err != nil {
		log.Error("failed to create elasticsearch client", "error", err)
		os.Exit(1)
	}
	if err := esClient.EnsureIndex(ctx, cfg.ES.IndexName, []byte(search.IndexMapping)); err != nil {
		log.Error("failed to ensure elasticsearch index", "error", err)
		os.Exit(1)
	}

	profilesRepo := profiles.NewRepository(dbPool)

	rows, err := dbPool.Query(ctx, `SELECT id FROM profiles ORDER BY created_at`)
	if err != nil {
		log.Error("failed to list profiles", "error", err)
		os.Exit(1)
	}
	var profileIDs []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			log.Error("failed to scan profile id", "error", err)
			os.Exit(1)
		}
		profileIDs = append(profileIDs, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		log.Error("failed while listing profiles", "error", err)
		os.Exit(1)
	}

	log.Info("reindex starting", "profile_count", len(profileIDs))

	var indexed, failed int
	for _, id := range profileIDs {
		if err := indexProfile(ctx, profilesRepo, esClient, cfg.ES.IndexName, id); err != nil {
			log.Error("failed to index profile", "profile_id", id, "error", err)
			failed++
			continue
		}
		indexed++
	}

	log.Info("reindex complete", "indexed", indexed, "failed", failed)
	if failed > 0 {
		os.Exit(1)
	}
}

// indexProfile mirrors cmd/worker's handler for a profile.updated event —
// duplicated rather than shared (worker's is an unexported package-main
// function) since this is a small, one-off ops tool, not something worth
// factoring a shared package out for.
func indexProfile(ctx context.Context, repo *profiles.Repository, es *elasticsearch.Client, indexName, profileID string) error {
	p, err := repo.GetByID(ctx, profileID)
	if err != nil {
		return err
	}
	// Demo profiles (see internal/demo) are never real search results —
	// they must only ever appear via the dedicated demo swipe-deck
	// endpoint. Skip indexing entirely rather than filtering at query
	// time, so a bug in the query side can't accidentally surface one.
	if p.IsDemo {
		return nil
	}

	photos, err := repo.ListPhotos(ctx, p.ID)
	if err != nil {
		return err
	}
	var photoURL *string
	if len(photos) > 0 {
		photoURL = &photos[0].URL
	}

	var dob *string
	if p.DateOfBirth != nil {
		v := p.DateOfBirth.Format("2006-01-02")
		dob = &v
	}

	doc := search.ProfileDocument{
		ProfileID:         p.ID,
		ProfileCode:       p.ProfileCode,
		UserID:            p.UserID,
		FullName:          p.FullName,
		DateOfBirth:       dob,
		Gender:            p.Gender,
		MaritalStatus:     p.MaritalStatus,
		Religion:          p.Religion,
		Community:         p.Community,
		Education:         p.Education,
		Occupation:        p.Occupation,
		City:              p.City,
		State:             p.State,
		AnnualIncomeINR:   p.AnnualIncomeINR,
		Diet:              p.Diet,
		Visibility:        p.Visibility,
		PhotoURL:          photoURL,
		CreatedAt:         p.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		HeightCM:          p.HeightCM,
		Manglik:           p.Manglik,
		MatchmakingOptOut: p.MatchmakingOptOut,
	}

	return es.IndexDocument(ctx, indexName, p.ID, doc)
}
