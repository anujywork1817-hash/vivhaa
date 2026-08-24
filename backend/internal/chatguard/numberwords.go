package chatguard

import (
	"regexp"
	"sort"
	"strings"
)

// numberwords.go detects phone numbers spelled out as words ("nine eight
// seven six five four three two one zero"), including words run together
// without spaces ("ninezero...") and separated by light punctuation
// ("nine-eight-seven...").
//
// This is intentionally conservative: a single stray number word ("I'll
// be there at nine") must never trigger a block. We only flag a run of
// *consecutive* digit-words (nothing but digit-words and light
// punctuation/whitespace between them) whose combined digit count matches
// a real phone-number shape (10, 11 with trunk 0, or 12 with 91 prefix) —
// the same shape check phone.go uses, so "strongly indicates a phone
// number" per Phase 5 rather than "contains number words at all".

var wordDigit = map[string]int{
	"zero": 0, "oh": 0, "o": 0,
	"one": 1, "two": 2, "three": 3, "four": 4, "for": 4,
	"five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
	// Common Hindi digit words, transliterated — best-effort per Phase 5's
	// "where practical", not an exhaustive multilingual NLP model.
	"shunya": 0, "sunya": 0,
	"ek": 1, "do": 2, "teen": 3, "char": 4, "chaar": 4,
	"paanch": 5, "panch": 5, "chhe": 6, "che": 6, "saat": 7,
	"aath": 8, "nau": 9,
}

// wordKeysByLenDesc lets the single-token parser (for "ninezero" style
// run-together words) greedily match the longest known word first, so
// "four" isn't mis-split as "for"+... or similar overlaps.
var wordKeysByLenDesc = func() []string {
	keys := make([]string, 0, len(wordDigit))
	for k := range wordDigit {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return len(keys[i]) > len(keys[j]) })
	return keys
}()

var wordSplitRe = regexp.MustCompile(`[A-Za-z]+`)

// parseDigitToken attempts to fully parse a single alphabetic token as one
// or more concatenated digit-words (e.g. "ninezero" -> [9,0]). Returns
// (digits, true) only if the ENTIRE token is consumed as digit-words —
// a token like "nineteen" or "ninja" must not partially match and leak
// through as a false positive.
func parseDigitToken(tok string) ([]int, bool) {
	tok = strings.ToLower(tok)
	if d, ok := wordDigit[tok]; ok {
		return []int{d}, true
	}
	if len(tok) < 6 { // shortest possible 2-word concatenation is "oh"+"oh" etc.; skip short tokens fast
		return nil, false
	}
	var digits []int
	remaining := tok
	for len(remaining) > 0 {
		matched := false
		for _, k := range wordKeysByLenDesc {
			if len(k) < 2 {
				continue // skip single-letter "o" as a concatenation component — too noisy
			}
			if strings.HasPrefix(remaining, k) {
				digits = append(digits, wordDigit[k])
				remaining = remaining[len(k):]
				matched = true
				break
			}
		}
		if !matched {
			return nil, false
		}
	}
	if len(digits) < 2 {
		return nil, false
	}
	return digits, true
}

// detectNumberWords reports whether body contains a spelled-out sequence
// of digit-words whose length and shape strongly indicate a phone number.
func detectNumberWords(body string) bool {
	tokens := wordSplitRe.FindAllString(body, -1)

	var run []int
	flush := func() bool {
		ok := len(run) > 0 && isPhoneShaped(run)
		run = nil
		return ok
	}

	for _, tok := range tokens {
		digits, ok := parseDigitToken(tok)
		if !ok {
			if flush() {
				return true
			}
			continue
		}
		run = append(run, digits...)
	}
	return flush()
}
