package chatguard

import "regexp"

// email.go detects standard and obfuscated email addresses. Obfuscation
// forms ("name [at] example [dot] com", "name at example dot com",
// "name @ example . com") are normalized to a canonical "@"/"." form
// first, then matched with one standard email regex — this keeps the
// regex itself simple and auditable while still catching the common
// evasions, rather than growing one unreadable mega-pattern.

var (
	standardEmailRe = regexp.MustCompile(`(?i)[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}`)

	// Matches "[at]", "(at)", " at ", "[dot]", "(dot)", " dot " as
	// stand-ins for "@"/"." — case-insensitive, tolerant of the brackets
	// being present or not, and of surrounding whitespace variance.
	atWordRe  = regexp.MustCompile(`(?i)\s*[\[\(]?\s*at\s*[\]\)]?\s*`)
	dotWordRe = regexp.MustCompile(`(?i)\s*[\[\(]?\s*dot\s*[\]\)]?\s*`)
	atSignRe  = regexp.MustCompile(`\s*@\s*`)
	dotSignRe = regexp.MustCompile(`\s*\.\s*`)
)

// detectEmail reports whether body contains an email address, standard
// or lightly obfuscated.
func detectEmail(body string) bool {
	if standardEmailRe.MatchString(body) {
		return true
	}

	// Build a de-obfuscated candidate: collapse " @ " -> "@", " . " -> ".",
	// "[at]"/" at " -> "@", "[dot]"/" dot " -> "." — then re-run the
	// standard regex. Order matters: word forms first (they're longer and
	// more specific), then loose spacing around literal signs.
	candidate := atWordRe.ReplaceAllString(body, "@")
	candidate = dotWordRe.ReplaceAllString(candidate, ".")
	candidate = atSignRe.ReplaceAllString(candidate, "@")
	candidate = dotSignRe.ReplaceAllString(candidate, ".")

	return standardEmailRe.MatchString(candidate)
}
