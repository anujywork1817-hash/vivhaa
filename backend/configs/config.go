package configs

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

type Config struct {
	Env      string
	HTTP     HTTPConfig
	DB       DBConfig
	Redis    RedisConfig
	JWT      JWTConfig
	S3       S3Config
	Razorpay RazorpayConfig
	Kafka    KafkaConfig
	ES       ElasticsearchConfig
	CORS     CORSConfig
	Google   GoogleAuthConfig
	AI       AIConfig
	FCM      FCMConfig
	WebRTC   WebRTCConfig
}

type HTTPConfig struct {
	Port string
}

type DBConfig struct {
	Host            string
	Port            string
	User            string
	Password        string
	Name            string
	SSLMode         string
	MaxOpenConns    int32
	MaxIdleConns    int32
	ConnMaxLifetime time.Duration
}

func (d DBConfig) DSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=%s",
		d.User, d.Password, d.Host, d.Port, d.Name, d.SSLMode,
	)
}

type RedisConfig struct {
	Addr     string
	Password string
	DB       int
}

type JWTConfig struct {
	AccessSecret  string
	RefreshSecret string
	AccessTTL     time.Duration
	RefreshTTL    time.Duration
}

// S3Config configures the object storage client. Endpoint/UsePathStyle
// let this point at a local MinIO instance in dev and real AWS S3 in
// staging/prod (leave Endpoint empty to use AWS's default endpoints).
//
// DocsBucket is a *separate, private* bucket for verification documents
// (government ID, selfies) — it must never get the public-read policy
// the profile-photos Bucket gets (see docker-compose's minio-init).
// Access is only ever via short-lived presigned URLs (pkg/s3's
// PresignDocURL), generated on demand, never stored.
//
// PublicEndpoint matters specifically for presigning: Endpoint is the
// address the API *container* uses to reach the storage backend (e.g.
// "http://minio:9000", a Docker-internal hostname), but a presigned URL
// is handed to an admin's browser outside that network — it must be
// signed against an address the browser can actually resolve, or every
// signed link 404s. Falls back to Endpoint when unset, which is correct
// for real AWS S3 (both empty/regional and already public) but must be
// set explicitly for local MinIO (the dev machine's LAN IP).
type S3Config struct {
	Endpoint       string
	PublicEndpoint string
	Region         string
	Bucket         string
	DocsBucket     string
	AccessKey      string
	SecretKey      string
	UsePathStyle   bool
	PublicBaseURL  string
}

// RazorpayConfig configures the payment gateway. When KeyID/KeySecret are
// left empty (the dev default), internal/payments falls back to a mock
// gateway so the checkout -> verify -> subscription-activation flow can be
// exercised end to end without a real Razorpay account.
type RazorpayConfig struct {
	KeyID         string
	KeySecret     string
	WebhookSecret string
}

// KafkaConfig configures the async event bus. Brokers is a comma-separated
// list; ConsumerGroup lets cmd/worker and cmd/notification run their own
// independent consumer groups against the same topics.
type KafkaConfig struct {
	Brokers []string
}

// ElasticsearchConfig configures the search index client.
type ElasticsearchConfig struct {
	Addresses []string
	IndexName string
}

// CORSConfig controls which browser origins may call the API. In dev,
// AllowAllOrigins defaults to true since the Flutter web dev server picks
// a random port every run; set CORS_ALLOWED_ORIGINS in prod to a real
// comma-separated allowlist instead.
type CORSConfig struct {
	AllowAllOrigins bool
	AllowedOrigins  []string
}

// GoogleAuthConfig lists the OAuth client IDs whose ID tokens we accept
// (Google issues a token per client type — web, Android, iOS — sharing
// one Google Cloud project, so this is typically 1-3 IDs). Empty means
// Google Sign-In is unconfigured and POST /auth/google always rejects.
type GoogleAuthConfig struct {
	AllowedClientIDs []string
}

// AIConfig configures the Groq-backed AI assistant. Empty APIKey means
// the assistant is unconfigured and /ai/* endpoints return a clear
// "not configured" error rather than failing obscurely.
type AIConfig struct {
	GroqAPIKey string
	Model      string
}

// Load reads configuration from environment variables, loading a local
// .env file first (if present) for developer convenience. Env vars set
// in the actual environment always take precedence over .env values.
//
// Fails fast (non-nil error) instead of booting with a dangerous default:
// APP_ENV must be explicitly "dev" or "prod" (defaulting to the safe
// choice, "prod", if unset — dev mode, which leaks OTPs in API responses
// and opens CORS to all origins, must be an explicit opt-in, never a
// silent default), and JWT_ACCESS_SECRET / JWT_REFRESH_SECRET must be set
// explicitly with no fallback — a hardcoded fallback secret is published
// in this source tree and lets anyone forge a valid token for any user.
func Load() (*Config, error) {
	_ = godotenv.Load()

	env := getEnv("APP_ENV", "prod")
	if env != "dev" && env != "prod" {
		return nil, fmt.Errorf("configs: APP_ENV must be \"dev\" or \"prod\" (got %q)", env)
	}
	devMode := env == "dev"

	accessSecret := os.Getenv("JWT_ACCESS_SECRET")
	refreshSecret := os.Getenv("JWT_REFRESH_SECRET")
	var missingSecrets []string
	if accessSecret == "" {
		missingSecrets = append(missingSecrets, "JWT_ACCESS_SECRET")
	}
	if refreshSecret == "" {
		missingSecrets = append(missingSecrets, "JWT_REFRESH_SECRET")
	}
	if len(missingSecrets) > 0 {
		return nil, fmt.Errorf("configs: required environment variable(s) not set: %s", strings.Join(missingSecrets, ", "))
	}
	// These exact values are published in this source tree (.env.example,
	// docker-compose.yml) as dev-only placeholders — accepting them outside
	// dev mode would just recreate the same forgeable-token problem by
	// copy-paste instead of by code fallback.
	if !devMode {
		if accessSecret == "dev-access-secret-change-me" {
			return nil, fmt.Errorf("configs: JWT_ACCESS_SECRET is still the published dev placeholder — set a real secret outside dev mode")
		}
		if refreshSecret == "dev-refresh-secret-change-me" {
			return nil, fmt.Errorf("configs: JWT_REFRESH_SECRET is still the published dev placeholder — set a real secret outside dev mode")
		}
	}

	cfg := &Config{
		Env: env,
		HTTP: HTTPConfig{
			Port: getEnv("HTTP_PORT", "8080"),
		},
		DB: DBConfig{
			Host:            getEnv("DB_HOST", "localhost"),
			Port:            getEnv("DB_PORT", "5432"),
			User:            getEnv("DB_USER", "postgres"),
			Password:        getEnv("DB_PASSWORD", "postgres"),
			Name:            getEnv("DB_NAME", "myapp"),
			SSLMode:         getEnv("DB_SSLMODE", "disable"),
			MaxOpenConns:    int32(getEnvInt("DB_MAX_OPEN_CONNS", 20)),
			MaxIdleConns:    int32(getEnvInt("DB_MAX_IDLE_CONNS", 5)),
			ConnMaxLifetime: time.Duration(getEnvInt("DB_CONN_MAX_LIFETIME_MIN", 30)) * time.Minute,
		},
		Redis: RedisConfig{
			Addr:     getEnv("REDIS_ADDR", "localhost:6379"),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getEnvInt("REDIS_DB", 0),
		},
		JWT: JWTConfig{
			AccessSecret:  accessSecret,
			RefreshSecret: refreshSecret,
			AccessTTL:     time.Duration(getEnvInt("JWT_ACCESS_TTL_MIN", 15)) * time.Minute,
			RefreshTTL:    time.Duration(getEnvInt("JWT_REFRESH_TTL_HOURS", 720)) * time.Hour,
		},
		S3: S3Config{
			Endpoint:       getEnv("S3_ENDPOINT", "http://localhost:59000"),
			PublicEndpoint: getEnv("S3_PUBLIC_ENDPOINT", ""),
			Region:         getEnv("S3_REGION", "us-east-1"),
			Bucket:         getEnv("S3_BUCKET", "matrimony-photos"),
			DocsBucket:     getEnv("S3_DOCS_BUCKET", "matrimony-verification-docs"),
			AccessKey:      getEnv("S3_ACCESS_KEY", "minioadmin"),
			SecretKey:      getEnv("S3_SECRET_KEY", "minioadmin123"),
			UsePathStyle:   getEnv("S3_USE_PATH_STYLE", "true") == "true",
			PublicBaseURL:  getEnv("S3_PUBLIC_BASE_URL", "http://localhost:59000/matrimony-photos"),
		},
		Razorpay: RazorpayConfig{
			KeyID:         getEnv("RAZORPAY_KEY_ID", ""),
			KeySecret:     getEnv("RAZORPAY_KEY_SECRET", ""),
			WebhookSecret: getEnv("RAZORPAY_WEBHOOK_SECRET", ""),
		},
		Kafka: KafkaConfig{
			Brokers: strings.Split(getEnv("KAFKA_BROKERS", "localhost:59092"), ","),
		},
		ES: ElasticsearchConfig{
			Addresses: strings.Split(getEnv("ES_ADDRESSES", "http://localhost:59200"), ","),
			IndexName: getEnv("ES_INDEX_NAME", "profiles"),
		},
		Google: GoogleAuthConfig{
			AllowedClientIDs: splitAndTrim(getEnv("GOOGLE_OAUTH_CLIENT_IDS", "")),
		},
		AI: AIConfig{
			GroqAPIKey: getEnv("GROQ_API_KEY", ""),
			Model:      getEnv("GROQ_MODEL", ""),
		},
		FCM: FCMConfig{
			CredentialsJSON: getEnv("FCM_CREDENTIALS_JSON", ""),
			CredentialsFile: getEnv("FCM_CREDENTIALS_FILE", ""),
			ProjectID:       getEnv("FCM_PROJECT_ID", ""),
		},
		WebRTC: WebRTCConfig{
			StunURLs:   splitAndTrim(getEnv("STUN_SERVER_URL", "stun:stun.l.google.com:19302")),
			TURNURL:    getEnv("TURN_SERVER_URL", ""),
			TURNSecret: getEnv("TURN_SECRET", ""),
		},
	}

	allowedOrigins := getEnv("CORS_ALLOWED_ORIGINS", "")
	cfg.CORS = CORSConfig{
		AllowAllOrigins: devMode && allowedOrigins == "",
		AllowedOrigins:  splitAndTrim(allowedOrigins),
	}

	return cfg, nil
}

func splitAndTrim(s string) []string {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if trimmed := strings.TrimSpace(p); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	v, ok := os.LookupEnv(key)
	if !ok || v == "" {
		return fallback
	}
	i, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return i
}

// FCMConfig configures Firebase Cloud Messaging for push notifications.
// Credentials come from a Firebase service-account key: either inlined as
// JSON (FCM_CREDENTIALS_JSON, convenient for container envs) or as a path
// to the downloaded file (FCM_CREDENTIALS_FILE). With neither set, push
// falls back to a console logger so the rest of the notification pipeline
// still runs in local dev.
type FCMConfig struct {
	CredentialsJSON string
	CredentialsFile string
	ProjectID       string
}

// Configured reports whether real FCM credentials were supplied.
func (c FCMConfig) Configured() bool {
	return c.CredentialsJSON != "" || c.CredentialsFile != ""
}

// WebRTCConfig configures ICE servers for video/voice calls.
// TURN_SERVER_URL/TURN_SECRET point at a self-hosted coturn instance
// (docker-compose's `coturn` service) — TURNSecret must match coturn's
// own `static-auth-secret` setting so it can validate the time-limited
// credentials internal/calls generates per call. Leaving TURN unset still
// works for most direct P2P connections via STUN alone; it just can't
// fall back to a relay when NAT traversal fails (symmetric NAT, some
// corporate firewalls).
type WebRTCConfig struct {
	StunURLs   []string
	TURNURL    string
	TURNSecret string
}

// Configured reports whether a TURN server is available to fall back on.
func (c WebRTCConfig) Configured() bool {
	return c.TURNURL != "" && c.TURNSecret != ""
}
