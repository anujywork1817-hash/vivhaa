// cmd/worker is a background consumer: it indexes profiles into
// Elasticsearch whenever internal/profiles publishes a profile.updated
// event, decoupling the indexing write from the request path.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"matrimony-backend/configs"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/queue"
	"matrimony-backend/internal/search"
	"matrimony-backend/pkg/database"
	"matrimony-backend/pkg/elasticsearch"
	"matrimony-backend/pkg/kafka"
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

	handler := func(ctx context.Context, _, value []byte) error {
		var event queue.ProfileUpdatedEvent
		if err := json.Unmarshal(value, &event); err != nil {
			return err
		}
		return indexProfile(ctx, profilesRepo, esClient, cfg.ES.IndexName, event.ProfileID)
	}

	log.Info("worker started", "topic", queue.TopicProfileUpdated)
	kafka.Consume(ctx, cfg.Kafka.Brokers, queue.TopicProfileUpdated, "worker", handler, log)
}

func indexProfile(ctx context.Context, repo *profiles.Repository, es *elasticsearch.Client, indexName, profileID string) error {
	p, err := repo.GetByID(ctx, profileID)
	if err != nil {
		return err
	}
	// Demo profiles (see internal/demo) must never surface in real search
	// results — only via the dedicated demo swipe-deck endpoint. Skip
	// indexing entirely rather than filtering at query time.
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
