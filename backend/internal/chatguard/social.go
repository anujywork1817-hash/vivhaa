package chatguard

import "regexp"

// social.go detects attempts to move the conversation to an external
// social/messaging service. This is intentionally *contextual* — merely
// saying "Instagram is a beautiful app" must be ALLOWED (Phase 7 example)
// — so a bare platform-name mention is never enough on its own. We only
// flag when a platform name (or a bare @handle / phone-app deep link)
// co-occurs with clear "move off-platform" intent language, or when an
// @handle appears standalone (handles have no other legitimate reason to
// appear in matrimonial chat).

var platformRe = regexp.MustCompile(`(?i)\b(whatsapp|whats app|w\.?a\.?|telegram|instagram|insta|facebook|fb|snapchat|snap|signal|skype|imo|hike|line app|wechat)\b`)

// intentRe matches phrasing that signals "go talk to me elsewhere" —
// "dm me", "message me on X", "find me on X", "contact me at X", "add me
// on X", "ping me on X", "reach me on X", "text me on X".
var intentRe = regexp.MustCompile(`(?i)\b(dm|pm|message|msg|text|ping|find|add|reach|contact|call|whatsapp)\s+me\b|\b(find|add|contact|message|msg|reach)\s+me\s+(on|at|via)\b`)

// handleRe matches a bare @handle token (3-30 word chars after the @),
// which — unlike a platform name in prose — has no ordinary matrimonial-
// chat use case.
var handleRe = regexp.MustCompile(`(?:^|[\s(])@[A-Za-z0-9_.]{3,30}\b`)

func detectSocialHandle(body string) bool {
	if handleRe.MatchString(body) {
		return true
	}
	return platformRe.MatchString(body) && intentRe.MatchString(body)
}
