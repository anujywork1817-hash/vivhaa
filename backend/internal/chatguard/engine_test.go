package chatguard

import "testing"

func newTestEngine() *Engine {
	return NewEngine(Config{Enabled: true, AllowedDomains: []string{"vivah.app", "vivah.example"}})
}

func TestPhoneNumbers_Blocked(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"9876543210",
		"call me on 9876543210",
		"+91 9876543210",
		"+919876543210",
		"91 9876543210",
		"09876543210",
		"98 76 54 32 10",
		"98765-43210",
		"(98765) 43210",
		"98765 43210",
		"9876543210.",
		"my number is 9876-543-210",
		"9876543210!!",
		"9️⃣8️⃣7️⃣6️⃣5️⃣4️⃣3️⃣2️⃣1️⃣0️⃣", // digits with emoji variation selectors between
		"9876 543 210",
		"+91-98765-43210",
		"(+91) 98765-43210",
		"98,765,43,210",
		"my whatsapp 9876543210 pls save it",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision == Allow {
			t.Errorf("expected BLOCK for phone case %q, got ALLOW", c)
		}
	}
}

// TestPhoneNumbers_NonMobilePrefixStillBlocked is a regression test for a
// real bypass found in production testing: a 10-digit sequence that
// doesn't start with 6-9 (so isn't shaped like a real Indian mobile
// number) used to sail through untouched, e.g. spacing digits out one
// per space so each individual character looks harmless. Any bare
// 10-digit sequence is now blocked regardless of its first digit.
func TestPhoneNumbers_NonMobilePrefixStillBlocked(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"1 2 4 5 6 7 8 9 0 1",
		"1245678901",
		"0123456789",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision == Allow {
			t.Errorf("expected BLOCK for non-mobile-prefix 10-digit case %q, got ALLOW", c)
		}
	}
}

func TestPhoneNumbers_UnicodeDigits(t *testing.T) {
	e := newTestEngine()
	// Devanagari digits for 9876543210
	if r := e.ModerateText("९८७६५४३२१०"); r.Decision == Allow {
		t.Errorf("expected BLOCK for devanagari-digit phone number, got ALLOW")
	}
}

func TestNumberWords_Blocked(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"nine eight seven six five four three two one zero",
		"nine-eight-seven-six-five-four-three-two-one-zero",
		"nine, eight, seven, six, five, four, three, two, one, zero",
		"ninezeroeightsixfivefourthreetwooneeight",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision == Allow {
			t.Errorf("expected BLOCK for number-word case %q, got ALLOW", c)
		}
	}
}

func TestNumberWords_NotOverBlocked(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"I'll be there at nine",
		"one for all and all for one",
		"she scored a nine out of ten",
		"I have nine books",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision != Allow {
			t.Errorf("expected ALLOW for benign number-word case %q, got %v", c, r.Decision)
		}
	}
}

func TestEmail_Blocked(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"reach me at name@example.com",
		"name @ example.com",
		"name [at] example [dot] com",
		"name at example dot com",
		"NAME AT EXAMPLE DOT COM",
		"my mail is priya.sharma123@gmail.com",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision == Allow {
			t.Errorf("expected BLOCK for email case %q, got ALLOW", c)
		}
	}
}

func TestSocial_Blocked(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"DM me on Instagram",
		"message me on whatsapp",
		"find me on telegram @realuser123",
		"add me on snapchat",
		"@rahul_kumar99",
		"contact me at @priya.s",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision == Allow {
			t.Errorf("expected BLOCK for social case %q, got ALLOW", c)
		}
	}
}

func TestSocial_NotOverBlocked(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"Instagram is a beautiful app",
		"I saw that on facebook news today",
		"Telegram used to be a paper message service",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision != Allow {
			t.Errorf("expected ALLOW for benign social case %q, got %v", c, r.Decision)
		}
	}
}

func TestURL_Blocked(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"check my profile http://myprofile.com/xyz",
		"visit www.example-contact.com",
		"go to example dot com",
		"link: bit.ly/abc123",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision == Allow {
			t.Errorf("expected BLOCK for URL case %q, got ALLOW", c)
		}
	}
}

func TestURL_InternalDomainAllowed(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"check out https://vivah.app/p/abc123",
		"share this profile: vivah.example/profile/99",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision != Allow {
			t.Errorf("expected ALLOW for internal domain %q, got %v", c, r.Decision)
		}
	}
}

func TestLegitimateMessages_Allowed(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"Call me tomorrow after work",
		"I have 10 books",
		"My order number is 12345",
		"Let's meet at 10 AM",
		"Instagram is a beautiful app",
		"My pin code is 400001",
		"I scored 98 out of 100",
		"We matched on 21/03/2024",
		"See you at 9",
		"Room number 987",
	}
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision != Allow {
			t.Errorf("expected ALLOW for legitimate message %q, got %v (%v)", c, r.Decision, r.Category)
		}
	}
}

func TestDisabledEngineAllowsEverything(t *testing.T) {
	e := NewEngine(Config{Enabled: false})
	if r := e.ModerateText("9876543210 name@example.com"); r.Decision != Allow {
		t.Errorf("expected ALLOW when engine disabled, got %v", r.Decision)
	}
}

// TestAdversarial50 exercises >=50 distinct bypass attempts (Phase 19).
func TestAdversarial50(t *testing.T) {
	e := newTestEngine()
	cases := []string{
		"9876543210", "98765 43210", "98 765 432 10", "9-8-7-6-5-4-3-2-1-0",
		"9876543210.", "9876543210,", "9876543210!", "9876543210?",
		"(9876543210)", "[9876543210]", "{9876543210}", "9876543210/",
		"+919876543210", "+91 9876543210", "+91-9876543210", "0091 9876543210",
		"91-9876543210", "0-9876543210", "09876543210",
		"98•76•54•32•10", "98.76.54.32.10", "98,76,54,32,10",
		"9876543210 ", " 9876543210", "\t9876543210\n",
		"9876543210​", "987​6543210", "9876⁠543210",
		"९८७६५४३२१०", "９８７６５４３２１０",
		"nine eight seven six five four three two one zero",
		"NINE EIGHT SEVEN SIX FIVE FOUR THREE TWO ONE ZERO",
		"Nine-Eight-Seven-Six-Five-Four-Three-Two-One-Zero",
		"nine   eight   seven   six   five   four   three   two   one   zero",
		"name@example.com", "name@ example.com", "name @example.com",
		"name @ example . com", "name[at]example[dot]com", "name at example dot com",
		"NAME AT EXAMPLE DOT COM", "name(at)example(dot)com",
		"DM me on whatsapp", "msg me on telegram", "find me on insta",
		"add me on FB", "ping me on Signal", "reach me on skype",
		"@my_real_handle", "contact @handle123 please",
		"www.externalsite.com", "http://externalsite.com/x",
		"https://externalsite.com", "externalsite dot com",
		"bit.ly/xyz123", "tinyurl.com/abc",
		"call me on 9876543210 ok?", "my num is nine eight seven six five four three two one zero ok",
	}
	failures := 0
	for _, c := range cases {
		if r := e.ModerateText(c); r.Decision == Allow {
			t.Logf("BYPASS FOUND: %q was allowed", c)
			failures++
		}
	}
	if failures > 0 {
		t.Errorf("%d/%d adversarial bypass cases were NOT blocked", failures, len(cases))
	}
}
