// cmd/scheduler runs daily batch jobs: warming the daily-matches Redis
// cache for every active user, and expiring subscriptions past their end
// date. It runs once immediately on startup (so the jobs are observable
// without waiting for midnight) and then once every 24h.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"matrimony-backend/configs"
	"matrimony-backend/internal/matchmaking"
	"matrimony-backend/internal/preferences"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/recommendation"
	"matrimony-backend/internal/subscriptions"
	"matrimony-backend/pkg/database"
	"matrimony-backend/pkg/logger"
	"matrimony-backend/pkg/redis"
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

	redisClient, err := redis.NewClient(ctx, cfg.Redis)
	if err != nil {
		log.Error("failed to connect to redis", "error", err)
		os.Exit(1)
	}
	defer redisClient.Close()

	profilesRepo := profiles.NewRepository(dbPool)
	preferencesRepo := preferences.NewRepository(dbPool)
	matchRepo := matchmaking.NewRepository(dbPool)
	recommendationService := recommendation.NewService(matchRepo, profilesRepo, preferencesRepo, redisClient)
	subscriptionsRepo := subscriptions.NewRepository(dbPool)

	runJobs(ctx, profilesRepo, subscriptionsRepo, recommendationService, log)

	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()

	log.Info("scheduler started, next run in 24h")
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			runJobs(ctx, profilesRepo, subscriptionsRepo, recommendationService, log)
		}
	}
}

func runJobs(ctx context.Context, profilesRepo *profiles.Repository, subscriptionsRepo *subscriptions.Repository, recommendationService *recommendation.Service, log *slog.Logger) {
	start := time.Now()
	log.Info("scheduler run starting")

	warmDailyMatches(ctx, profilesRepo, recommendationService, log)
	expireSubscriptions(ctx, subscriptionsRepo, log)

	log.Info("scheduler run complete", "duration", time.Since(start).String())
}

func warmDailyMatches(ctx context.Context, profilesRepo *profiles.Repository, recommendationService *recommendation.Service, log *slog.Logger) {
	userIDs, err := profilesRepo.ListPublicUserIDs(ctx)
	if err != nil {
		log.Error("failed to list users for daily match warmup", "error", err)
		return
	}

	warmed, failed := 0, 0
	for _, userID := range userIDs {
		if _, err := recommendationService.GetDaily(ctx, userID); err != nil {
			failed++
			continue
		}
		warmed++
	}
	log.Info("daily matches cache warmed", "warmed", warmed, "failed", failed, "total", len(userIDs))
}

func expireSubscriptions(ctx context.Context, subscriptionsRepo *subscriptions.Repository, log *slog.Logger) {
	count, err := subscriptionsRepo.ExpireEnded(ctx)
	if err != nil {
		log.Error("failed to expire subscriptions", "error", err)
	} else {
		log.Info("expired subscriptions past their end date", "count", count)
	}

	staleCount, err := subscriptionsRepo.ExpireStalePending(ctx)
	if err != nil {
		log.Error("failed to expire stale pending subscriptions", "error", err)
		return
	}
	log.Info("cancelled stale pending subscriptions", "count", staleCount)
}
