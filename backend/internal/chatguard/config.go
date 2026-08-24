package chatguard

// Config configures the moderation Engine. It intentionally holds only
// what detection needs (allowed domains) — abuse thresholds, restriction
// durations etc. are a chat-package concern (they involve persisted
// state per user), not this pure-detection package's.
type Config struct {
	// Enabled lets moderation be killed via config in an emergency
	// (e.g. a bad false-positive wave) without a deploy that touches code.
	Enabled bool

	// AllowedDomains are hosts the app itself controls (e.g. its own
	// share-link domain, a help-center domain) — URLs to these are never
	// blocked as "external links".
	AllowedDomains []string
}

// Engine is the reusable moderation service described in Phase 2's
// ModerateChatMessage interface. It is safe for concurrent use (holds no
// mutable state beyond its immutable Config).
type Engine struct {
	cfg Config
}

func NewEngine(cfg Config) *Engine {
	return &Engine{cfg: cfg}
}

// ModerateText runs the full text-detection pipeline over one message
// body and returns a policy decision. Detection order matters only in
// that it determines which Category is reported when multiple issues are
// present — the Decision to block is the same either way.
func (e *Engine) ModerateText(body string) Result {
	if !e.cfg.Enabled {
		return allow()
	}
	if body == "" {
		return allow()
	}

	if detectPhone(body) {
		return block(BlockContactInfo, CategoryPhoneNumber, "", "phone-like digit sequence")
	}
	if detectNumberWords(body) {
		return block(BlockContactInfo, CategoryNumberWords, "", "spelled-out phone-like sequence")
	}
	if detectEmail(body) {
		return block(BlockContactInfo, CategoryEmail, "", "email-like pattern")
	}
	if detectSocialHandle(body) {
		return block(BlockSocialHandle, CategorySocialHandle, "", "social handle / off-platform intent")
	}
	if detectExternalLink(body, e.cfg.AllowedDomains) {
		return block(BlockExternalLink, CategoryExternalLink, "", "external link")
	}

	return allow()
}
