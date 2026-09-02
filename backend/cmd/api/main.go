package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/getsentry/sentry-go"
	sentrygin "github.com/getsentry/sentry-go/gin"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"

	"matrimony-backend/configs"
	"matrimony-backend/internal/admin"
	"matrimony-backend/internal/ai"
	"matrimony-backend/internal/analytics"
	"matrimony-backend/internal/auth"
	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/calls"
	"matrimony-backend/internal/chat"
	"matrimony-backend/internal/chatguard"
	"matrimony-backend/internal/coupons"
	"matrimony-backend/internal/demo"
	"matrimony-backend/internal/devices"
	"matrimony-backend/internal/email"
	"matrimony-backend/internal/favourites"
	"matrimony-backend/internal/interests"
	"matrimony-backend/internal/matchmaking"
	"matrimony-backend/internal/middleware"
	"matrimony-backend/internal/moderation"
	"matrimony-backend/internal/notifications"
	"matrimony-backend/internal/payments"
	"matrimony-backend/internal/preferences"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/queue"
	"matrimony-backend/internal/recommendation"
	"matrimony-backend/internal/reference"
	"matrimony-backend/internal/reports"
	"matrimony-backend/internal/savedsearches"
	"matrimony-backend/internal/search"
	"matrimony-backend/internal/shortlisted"
	"matrimony-backend/internal/sms"
	"matrimony-backend/internal/storage"
	"matrimony-backend/internal/subscriptions"
	"matrimony-backend/internal/unlock"
	"matrimony-backend/internal/users"
	"matrimony-backend/internal/verification"
	"matrimony-backend/internal/visitors"
	appwebsocket "matrimony-backend/internal/websocket"
	"matrimony-backend/pkg/database"
	"matrimony-backend/pkg/elasticsearch"
	"matrimony-backend/pkg/googleauth"
	"matrimony-backend/pkg/health"
	"matrimony-backend/pkg/groq"
	"matrimony-backend/pkg/jwt"
	"matrimony-backend/pkg/kafka"
	"matrimony-backend/pkg/logger"
	"matrimony-backend/pkg/ratelimit"
	"matrimony-backend/pkg/redis"
	"matrimony-backend/pkg/response"
	"matrimony-backend/pkg/s3"
)

func main() {
	cfg, err := configs.Load()
	if err != nil {
		// A raw panic() here would print a stack trace, making an
		// intentional "you forgot to configure something" exit look like
		// a crash bug. There's no logger yet (it needs cfg.Env), so this
		// is the one place in main() that writes directly to stderr.
		fmt.Fprintln(os.Stderr, "fatal: invalid configuration:", err)
		os.Exit(1)
	}

	log := logger.New(cfg.Env)

	// --- Sentry init (do this first, before anything else can panic/error) ---
	// No hardcoded fallback DSN: a value baked into this source file is
	// visible to anyone reading it, letting them flood the project's
	// error tracking with fabricated events. Sentry is simply disabled
	// (sentry.Init with an empty Dsn is a documented no-op) until
	// SENTRY_DSN is actually set.
	sentryDsn := os.Getenv("SENTRY_DSN")
	err = sentry.Init(sentry.ClientOptions{
		Dsn:              sentryDsn,
		Environment:      cfg.Env,
		EnableTracing:    true,
		TracesSampleRate: 1.0, // lower this in prod (e.g. 0.2) once traffic is real
	})
	if err != nil {
		log.Error("sentry.Init failed", "error", err)
	}
	// Flush buffered events before the program exits (normal or panic)
	defer sentry.Flush(2 * time.Second)
	// BUG: sentry.Recover() (bare, no repanic) swallows a startup panic
	// completely — Sentry gets the event, but the process just returns
	// from main() normally afterward: exit code 0, nothing on
	// stdout/stderr, nothing in `docker logs`. A panic during service
	// wiring (anywhere between here and srv.ListenAndServe) looked
	// identical to a clean, silent shutdown from outside the process,
	// which is exactly what made this so hard to diagnose without Sentry
	// dashboard access. Capturing manually and re-panicking (after the
	// deferred Flush above has already run, since defers execute LIFO)
	// means a startup panic now shows up in the container's own logs.
	defer func() {
		if r := recover(); r != nil {
			sentry.CurrentHub().Recover(r)
			panic(r)
		}
	}()

	ctx := context.Background()

	dbPool, err := database.NewPool(ctx, cfg.DB)
	if err != nil {
		log.Error("failed to connect to database", "error", err)
		sentry.CaptureException(err)
		os.Exit(1)
	}
	defer dbPool.Close()
	log.Info("connected to database", "host", cfg.DB.Host, "name", cfg.DB.Name)

	redisClient, err := redis.NewClient(ctx, cfg.Redis)
	if err != nil {
		log.Error("failed to connect to redis", "error", err)
		sentry.CaptureException(err)
		os.Exit(1)
	}
	defer redisClient.Close()
	log.Info("connected to redis", "addr", cfg.Redis.Addr)

	rateLimiter := ratelimit.New(redisClient)

	s3Client, err := s3.NewClient(ctx, cfg.S3)
	if err != nil {
		log.Error("failed to create s3 client", "error", err)
		sentry.CaptureException(err)
		os.Exit(1)
	}
	if cfg.Env == "dev" {
		if err := s3Client.EnsureBucket(ctx); err != nil {
			log.Warn("failed to ensure s3 bucket exists", "error", err)
		}
		if err := s3Client.EnsureDocsBucket(ctx); err != nil {
			log.Warn("failed to ensure s3 docs bucket exists", "error", err)
		}
	}
	log.Info("connected to s3", "endpoint", cfg.S3.Endpoint, "bucket", cfg.S3.Bucket, "docs_bucket", cfg.S3.DocsBucket)

	kafkaProducer := kafka.NewProducer(cfg.Kafka.Brokers)
	defer kafkaProducer.Close()
	publisher := queue.NewPublisher(kafkaProducer)
	log.Info("connected to kafka", "brokers", cfg.Kafka.Brokers)

	esClient, err := elasticsearch.NewClient(cfg.ES)
	if err != nil {
		log.Error("failed to create elasticsearch client", "error", err)
		sentry.CaptureException(err)
		os.Exit(1)
	}
	if cfg.Env == "dev" {
		if err := esClient.EnsureIndex(ctx, cfg.ES.IndexName, []byte(search.IndexMapping)); err != nil {
			log.Warn("failed to ensure elasticsearch index exists", "error", err)
		}
	}
	log.Info("connected to elasticsearch", "addresses", cfg.ES.Addresses, "index", cfg.ES.IndexName)

	if cfg.Env == "prod" {
		gin.SetMode(gin.ReleaseMode)
	}
	router := gin.New()

	// --- Sentry Gin middleware: captures panics + lets you attach errors per-request ---
	router.Use(sentrygin.New(sentrygin.Options{
		Repanic:         true, // let gin.Recovery() still handle the actual recovery/500 response
		WaitForDelivery: false,
		Timeout:         3 * time.Second,
	}))
	router.Use(gin.Recovery())
	router.Use(middleware.RequestLog(log))

	router.Use(cors.New(cors.Config{
		AllowAllOrigins: cfg.CORS.AllowAllOrigins,
		AllowOrigins:    cfg.CORS.AllowedOrigins,
		AllowMethods:    []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:    []string{"Origin", "Content-Type", "Authorization"},
		// Required for the browser to actually send/accept the httpOnly
		// access_token/refresh_token cookies auth/handler.go sets — a
		// cross-origin request (the admin panel is a separate origin from
		// the API) omits cookies entirely without this, regardless of
		// what the server's Set-Cookie response contains. Note this is
		// incompatible with AllowAllOrigins in a real browser (the CORS
		// spec forbids `Access-Control-Allow-Origin: *` alongside
		// credentials) — CORS_ALLOWED_ORIGINS must list the real admin
		// panel origin explicitly outside dev.
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))
	if cfg.CORS.AllowAllOrigins {
		log.Warn("CORS: allowing all origins (dev default) — set CORS_ALLOWED_ORIGINS in prod")
	}

	// Dependency reachability probes added after the 2026-08-24 incident,
	// where Kafka/Elasticsearch were unreachable (missing security-group
	// rules) and a missing storage bucket both went undetected until real
	// requests failed — /health only checked DB/Redis, so nothing caught
	// either until a user hit them.
	//
	// These run on a background interval rather than inline per-request:
	// an earlier version ran all 5 probes synchronously on every /health
	// call, which under a 1000-VU load test (hitting /health every
	// iteration) measurably degraded latency and throughput for the whole
	// service (p95 48ms -> 382ms). See pkg/health for the caching design.
	healthCheckInterval := 5 * time.Second
	if v := os.Getenv("HEALTH_CHECK_INTERVAL_SECONDS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			healthCheckInterval = time.Duration(n) * time.Second
		}
	}
	healthChecker := health.New(healthCheckInterval, 3*healthCheckInterval, 3*time.Second, log, map[string]health.Probe{
		"database": func(ctx context.Context) error { return dbPool.Ping(ctx) },
		"redis":    func(ctx context.Context) error { return redisClient.Ping(ctx).Err() },
		"elasticsearch": func(ctx context.Context) error {
			return esClient.Ping(ctx)
		},
		"kafka": func(ctx context.Context) error {
			return kafkaProducer.Ping(ctx)
		},
		"storage": func(ctx context.Context) error {
			return s3Client.BucketsReachable(ctx)
		},
	})
	healthCheckerCtx, stopHealthChecker := context.WithCancel(context.Background())
	defer stopHealthChecker()
	healthChecker.Start(healthCheckerCtx)

	router.GET("/health", func(c *gin.Context) {
		snapshot := healthChecker.Snapshot()

		status := http.StatusOK
		body := gin.H{"status": "ok"}
		for _, name := range []string{"database", "redis", "elasticsearch", "kafka", "storage"} {
			result := snapshot[name]
			if !result.OK {
				status = http.StatusServiceUnavailable
				body[name] = result.Message
			} else {
				body[name] = "ok"
			}
		}

		response.Success(c, status, body, gin.H{
			"env": cfg.Env,
		})
	})

	// The ALB health check probes "/" (not "/health"), so it needs its own
	// dependency-free route — otherwise it hits Gin's default 404 and EB
	// marks the environment Severe even though the app is running fine.
	// Deliberately no DB/Redis/etc. here: always 200, so it can't itself
	// cause health-check flapping.
	router.GET("/", func(c *gin.Context) {
		c.String(http.StatusOK, "OK")
	})

	accessIssuer := jwt.NewIssuer(cfg.JWT.AccessSecret, cfg.JWT.AccessTTL)
	smsSender := sms.NewConsoleSender(log)
	emailSender := email.NewConsoleSender(log)

	analyticsRepo := analytics.NewRepository(dbPool)
	analyticsService := analytics.NewService(analyticsRepo)

	googleVerifier := googleauth.NewVerifier(cfg.Google.AllowedClientIDs)
	if !googleVerifier.Configured() {
		log.Warn("GOOGLE_OAUTH_CLIENT_IDS not set, POST /auth/google will reject all requests")
	}

	authRepo := auth.NewRepository(dbPool)
	authService := auth.NewService(authRepo, smsSender, emailSender, accessIssuer, cfg.JWT.RefreshTTL, cfg.Env == "dev", analyticsService, googleVerifier, rateLimiter)
	authHandler := auth.NewHandler(authService, cfg.Env == "prod")

	usersRepo := users.NewRepository(dbPool)
	usersHandler := users.NewHandler(usersRepo)

	visitorsRepo := visitors.NewRepository(dbPool)
	visitorsService := visitors.NewService(visitorsRepo)
	visitorsHandler := visitors.NewHandler(visitorsService)

	subscriptionsRepo := subscriptions.NewRepository(dbPool)
	subscriptionsService := subscriptions.NewService(subscriptionsRepo)
	subscriptionsHandler := subscriptions.NewHandler(subscriptionsService)

	photoUploader := storage.NewPhotoUploader(s3Client)
	profilesRepo := profiles.NewRepository(dbPool)

	// Created ahead of profilesService (rather than in its usual spot
	// further down, alongside blockedHandler) — profiles.Service needs a
	// BlockChecker at construction time so a blocked profile can 404
	// instead of loading normally.
	blockedRepo := blocked.NewRepository(dbPool)

	profilesService := profiles.NewService(profilesRepo, photoUploader, visitorsService, usersRepo, subscriptionsService, publisher, blockedRepo)
	profilesHandler := profiles.NewHandler(profilesService)

	referenceStore, err := reference.New()
	if err != nil {
		log.Error("failed to load reference data", "error", err)
		os.Exit(1)
	}
	referenceHandler := reference.NewHandler(referenceStore)

	preferencesRepo := preferences.NewRepository(dbPool)
	preferencesService := preferences.NewService(preferencesRepo)
	preferencesHandler := preferences.NewHandler(preferencesService)

	savedSearchesRepo := savedsearches.NewRepository(dbPool)
	savedSearchesService := savedsearches.NewService(savedSearchesRepo)
	savedSearchesHandler := savedsearches.NewHandler(savedSearchesService)

	notificationsRepo := notifications.NewRepository(dbPool)
	notificationsService := notifications.NewService(notificationsRepo)
	notificationsHandler := notifications.NewHandler(notificationsService)

	blockedService := blocked.NewService(blockedRepo, profilesRepo)
	blockedHandler := blocked.NewHandler(blockedService)

	devicesRepo := devices.NewRepository(dbPool)
	devicesService := devices.NewService(devicesRepo)
	devicesHandler := devices.NewHandler(devicesService)

	groqClient := groq.NewClient(cfg.AI.GroqAPIKey, cfg.AI.Model)
	if !groqClient.Configured() {
		log.Warn("GROQ_API_KEY not set — AI assistant endpoints will return ai_not_configured")
	}
	aiRepo := ai.NewRepository(dbPool)
	aiService := ai.NewService(groqClient, aiRepo, profilesRepo, profilesService)
	aiHandler := ai.NewHandler(aiService)

	// Built before the services that push through it — chat, calls, and
	// interests all send events over the same hub.
	wsHub := appwebsocket.NewHub(ctx, redisClient, log)

	interestsRepo := interests.NewRepository(dbPool)
	interestsService := interests.NewService(interestsRepo, profilesRepo, blockedRepo, publisher, analyticsService, wsHub)
	interestsHandler := interests.NewHandler(interestsService)

	favouritesRepo := favourites.NewRepository(dbPool)
	favouritesService := favourites.NewService(favouritesRepo, profilesRepo, blockedRepo)
	favouritesHandler := favourites.NewHandler(favouritesService)

	shortlistedRepo := shortlisted.NewRepository(dbPool)
	shortlistedService := shortlisted.NewService(shortlistedRepo, profilesRepo, blockedRepo)
	shortlistedHandler := shortlisted.NewHandler(shortlistedService)

	searchRepo := search.NewRepository(esClient, cfg.ES.IndexName)
	searchService := search.NewService(searchRepo, blockedRepo, profilesRepo)
	searchHandler := search.NewHandler(searchService)

	matchRepo := matchmaking.NewRepository(dbPool)
	recommendationService := recommendation.NewService(matchRepo, profilesRepo, preferencesRepo, redisClient)
	recommendationHandler := recommendation.NewHandler(recommendationService)

	chatGuard := chatguard.NewEngine(chatguard.Config{
		Enabled:        cfg.Moderation.Enabled,
		AllowedDomains: cfg.Moderation.AllowedDomains,
	})
	chatRepo := chat.NewRepository(dbPool)
	chatService := chat.NewService(chatRepo, interestsRepo, blockedRepo, profilesService, publisher, subscriptionsService, analyticsService, wsHub, chatGuard, chat.AbuseConfig{
		RestrictThreshold: cfg.Moderation.RestrictThreshold,
		RestrictDuration:  cfg.Moderation.RestrictDuration,
		ReviewThreshold:   cfg.Moderation.ReviewThreshold,
	}, rateLimiter)
	chatHandler := chat.NewHandler(chatService, photoUploader)

	callsRepo := calls.NewRepository(dbPool)
	callsService := calls.NewService(callsRepo, interestsRepo, blockedRepo, profilesRepo, wsHub, publisher, calls.Config{
		StunURLs:   cfg.WebRTC.StunURLs,
		TURNURL:    cfg.WebRTC.TURNURL,
		TURNSecret: cfg.WebRTC.TURNSecret,
	})
	callsHandler := calls.NewHandler(callsService)
	if !cfg.WebRTC.Configured() {
		log.Warn("TURN_SERVER_URL/TURN_SECRET not set — calls will rely on STUN/direct P2P only, with no relay fallback")
	}

	chatWSHandler := chat.NewWSHandler(chatService, callsService, wsHub, accessIssuer, cfg.CORS.AllowAllOrigins, cfg.CORS.AllowedOrigins)

	docUploader := storage.NewDocumentUploader(s3Client)
	verificationRepo := verification.NewRepository(dbPool)
	verificationService := verification.NewService(verificationRepo, docUploader, profilesRepo)
	verificationHandler := verification.NewHandler(verificationService)

	reportsRepo := reports.NewRepository(dbPool)
	reportsService := reports.NewService(reportsRepo, profilesRepo)
	reportsHandler := reports.NewHandler(reportsService)

	moderationRepo := moderation.NewRepository(dbPool)
	moderationService := moderation.NewService(moderationRepo)
	moderationHandler := moderation.NewHandler(moderationService)

	couponsRepo := coupons.NewRepository(dbPool)
	couponsService := coupons.NewService(couponsRepo)

	// strict=true outside dev mode: NewGateway refuses to fall back to the
	// mock gateway in prod rather than booting on it with just a log line
	// (the mock's signature check accepts a publicly known constant
	// secret — silently running on it in prod means anyone can activate a
	// paid plan for free).
	paymentGateway, err := payments.NewGateway(cfg.Razorpay, cfg.Env != "dev")
	if err != nil {
		log.Error("failed to initialize payment gateway", "error", err)
		sentry.CaptureException(err)
		os.Exit(1)
	}
	if cfg.Razorpay.KeyID == "" || cfg.Razorpay.KeySecret == "" {
		log.Warn("RAZORPAY_KEY_ID/RAZORPAY_KEY_SECRET not set, using mock payment gateway (dev/testing only)")
	}
	paymentsRepo := payments.NewRepository(dbPool)
	paymentsService := payments.NewService(paymentsRepo, subscriptionsRepo, couponsService, paymentGateway, cfg.Razorpay.WebhookSecret)
	paymentsHandler := payments.NewHandler(paymentsService)

	// demo (free swipe-deck hook) and unlock (₹1 one-time paywall gate) —
	// see internal/demo and internal/unlock. unlock reuses the same
	// paymentGateway internal/payments wired up above, and requireUnlocked
	// is the middleware every real (non-demo) feature group below is
	// gated behind.
	demoService := demo.NewService(profilesRepo)
	demoHandler := demo.NewHandler(demoService)

	unlockRepo := unlock.NewRepository(dbPool)
	unlockService := unlock.NewService(unlockRepo, usersRepo, paymentGateway)
	unlockHandler := unlock.NewHandler(unlockService)
	requireUnlocked := middleware.RequireUnlocked(usersRepo)

	adminRepo := admin.NewRepository(dbPool)
	adminService := admin.NewService(adminRepo, profilesRepo, subscriptionsRepo, verificationRepo, docUploader)
	adminHandler := admin.NewHandler(adminService)

	api := router.Group("/")
	auth.RegisterRoutes(api, authHandler, accessIssuer, rateLimiter)
	users.RegisterRoutes(api, usersHandler, accessIssuer)
	profiles.RegisterRoutes(api, profilesHandler, accessIssuer)
	preferences.RegisterRoutes(api, preferencesHandler, accessIssuer)
	savedsearches.RegisterRoutes(api, savedSearchesHandler, accessIssuer)
	interests.RegisterRoutes(api, interestsHandler, accessIssuer, rateLimiter, requireUnlocked)
	favourites.RegisterRoutes(api, favouritesHandler, accessIssuer, requireUnlocked)
	shortlisted.RegisterRoutes(api, shortlistedHandler, accessIssuer, requireUnlocked)
	blocked.RegisterRoutes(api, blockedHandler, accessIssuer)
	devices.RegisterRoutes(api, devicesHandler, accessIssuer, rateLimiter)
	ai.RegisterRoutes(api, aiHandler, accessIssuer)
	search.RegisterRoutes(api, searchHandler, accessIssuer, requireUnlocked)
	recommendation.RegisterRoutes(api, recommendationHandler, accessIssuer, requireUnlocked)
	notifications.RegisterRoutes(api, notificationsHandler, accessIssuer)
	chat.RegisterRoutes(api, chatHandler, chatWSHandler, accessIssuer, requireUnlocked)
	calls.RegisterRoutes(api, callsHandler, accessIssuer, requireUnlocked)
	visitors.RegisterRoutes(api, visitorsHandler, accessIssuer, requireUnlocked)
	verification.RegisterRoutes(api, verificationHandler, accessIssuer)
	reports.RegisterRoutes(api, reportsHandler, accessIssuer)
	moderation.RegisterRoutes(api, moderationHandler, accessIssuer)
	subscriptions.RegisterRoutes(api, subscriptionsHandler, accessIssuer)
	payments.RegisterRoutes(api, paymentsHandler, accessIssuer, paymentGateway)
	admin.RegisterRoutes(api, adminHandler, accessIssuer)
	reference.RegisterRoutes(api, referenceHandler, accessIssuer)
	demo.RegisterRoutes(api, demoHandler, accessIssuer)
	unlock.RegisterRoutes(api, unlockHandler, accessIssuer, paymentGateway)

	srv := &http.Server{
		Addr:    ":" + cfg.HTTP.Port,
		Handler: router,
	}

	go func() {
		log.Info("starting server", "port", cfg.HTTP.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error("server error", "error", err)
			sentry.CaptureException(err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Info("shutting down server")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error("forced shutdown", "error", err)
		sentry.CaptureException(err)
	}
}
