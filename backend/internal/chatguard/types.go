// Package chatguard is a dependency-free, server-side text moderation
// engine for detecting contact-information exchange attempts (phone
// numbers, emails, social handles, external links) in chat messages.
//
// It is deliberately pure — no DB, no HTTP, no config file I/O — so it can
// be unit tested exhaustively and reused from any call site (REST, WS,
// background reprocessing) without dragging in the rest of the app.
package chatguard

// Decision is the policy outcome for one piece of moderated content.
type Decision string

const (
	Allow                  Decision = "ALLOW"
	BlockContactInfo       Decision = "BLOCK_CONTACT_INFO"
	BlockExternalLink      Decision = "BLOCK_EXTERNAL_LINK"
	BlockSocialHandle      Decision = "BLOCK_SOCIAL_HANDLE"
	BlockSuspiciousContent Decision = "BLOCK_SUSPICIOUS_CONTENT"
	RequireReview          Decision = "REQUIRE_REVIEW"
)

// Category identifies *why* a decision was reached — kept separate from
// Decision so callers/logs can record what was found without that detail
// ever reaching the client (see Phase 15: never expose detection rules).
type Category string

const (
	CategoryNone         Category = ""
	CategoryPhoneNumber  Category = "phone_number"
	CategoryNumberWords  Category = "number_words"
	CategoryEmail        Category = "email"
	CategorySocialHandle Category = "social_handle"
	CategoryExternalLink Category = "external_link"
)

// Result is the structured outcome of moderating one message body. Internal
// detection details (Category, MatchedSpan) must never be serialized back
// to the client — only Decision (via a generic user-facing message) may
// ever leave the server. See chat.Service for the enforcement boundary.
type Result struct {
	Decision Decision
	Category Category

	// Normalized is the detection-only representation used to find the
	// match — never persisted, never shown to any user, and not the same
	// string as the original message (see normalize.go doc comment).
	Normalized string

	// MatchedSpan is a short excerpt of what triggered the block, for
	// server-side moderation logs only (Phase 21 forbids logging raw
	// contact info, so callers should NOT log this field verbatim —
	// it exists for local debugging / REQUIRE_REVIEW admin tooling that
	// explicitly needs it, not for routine logs).
	MatchedSpan string
}

func allow() Result { return Result{Decision: Allow} }

func block(decision Decision, category Category, normalized, span string) Result {
	return Result{Decision: decision, Category: category, Normalized: normalized, MatchedSpan: span}
}
