package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"matrimony-backend/internal/profiles"
	"matrimony-backend/pkg/groq"
)

var ErrNotConfigured = groq.ErrNotConfigured

const systemPrompt = `You are the Vivaha Assistant, built into an Indian matrimony app called Vivaha.
You help members with: writing/improving their profile "About Me", conversation starters for a match,
general relationship advice, and how-to questions about using the app (search, interests, shortlist,
chat, verification, subscriptions). Keep replies warm, concise (a few sentences unless asked for more),
and appropriate for a matrimony context. You are not a licensed counselor — for serious personal or
safety issues, suggest they contact a professional or use the in-app Report/Block features.`

type Service struct {
	client       *groq.Client
	repo         *Repository
	profilesRepo *profiles.Repository
}

func NewService(client *groq.Client, repo *Repository, profilesRepo *profiles.Repository) *Service {
	return &Service{client: client, repo: repo, profilesRepo: profilesRepo}
}

func (s *Service) Configured() bool {
	return s.client.Configured()
}

// Chat appends the user's message, asks the model for a reply (with
// recent history as context), and persists the reply too.
func (s *Service) Chat(ctx context.Context, userID, message string) (MessageResponse, error) {
	if !s.client.Configured() {
		return MessageResponse{}, ErrNotConfigured
	}

	history, err := s.repo.History(ctx, userID)
	if err != nil {
		return MessageResponse{}, err
	}

	messages := []groq.Message{{Role: "system", Content: systemPrompt}}
	for _, m := range history {
		messages = append(messages, groq.Message{Role: m.Role, Content: m.Content})
	}
	messages = append(messages, groq.Message{Role: "user", Content: message})

	reply, err := s.client.Complete(ctx, messages)
	if err != nil {
		return MessageResponse{}, err
	}

	// BUG-H03: the user's turn used to be persisted *before* this call,
	// so any failure here (rate limit, timeout, network blip) left an
	// orphaned user message with no reply. The next Chat() call would
	// load that dangling turn as history and append another user
	// message right after it — two consecutive user-role entries with
	// no assistant reply between them, which several providers reject
	// outright and all of them handle as a malformed conversation.
	// Persisting both turns together, only once the call has actually
	// succeeded, means a failed request leaves no trace instead of a
	// permanently broken thread.
	if _, err := s.repo.Append(ctx, userID, "user", message); err != nil {
		return MessageResponse{}, err
	}
	saved, err := s.repo.Append(ctx, userID, "assistant", reply)
	if err != nil {
		return MessageResponse{}, err
	}
	return toResponse(saved), nil
}

func (s *Service) History(ctx context.Context, userID string) ([]MessageResponse, error) {
	rows, err := s.repo.History(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]MessageResponse, 0, len(rows))
	for _, m := range rows {
		out = append(out, toResponse(m))
	}
	return out, nil
}

// Icebreakers suggests opening messages for userID to send targetProfileID,
// based on both profiles' interests/profession.
func (s *Service) Icebreakers(ctx context.Context, userID, targetProfileID string) (IcebreakersResponse, error) {
	if !s.client.Configured() {
		return IcebreakersResponse{}, ErrNotConfigured
	}

	me, target, err := s.loadPair(ctx, userID, targetProfileID)
	if err != nil {
		return IcebreakersResponse{}, err
	}

	prompt := fmt.Sprintf(
		"Suggest 3 short, friendly icebreaker opening messages that %s could send to %s on a matrimony app.\n\n"+
			"About the sender:\n%s\n\nAbout the recipient:\n%s\n\n"+
			`Reply with ONLY a JSON array of 3 strings, no other text. Example: ["...", "...", "..."]`,
		describeName(me), describeName(target), describeProfile(me), describeProfile(target),
	)

	reply, err := s.client.Complete(ctx, []groq.Message{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: prompt},
	})
	if err != nil {
		return IcebreakersResponse{}, err
	}

	var icebreakers []string
	if err := json.Unmarshal([]byte(extractJSON(reply)), &icebreakers); err != nil || len(icebreakers) == 0 {
		// Model didn't follow the format — fall back to splitting lines
		// rather than failing the request outright.
		icebreakers = splitFallback(reply)
	}
	return IcebreakersResponse{Icebreakers: icebreakers}, nil
}

// MatchBlurb generates a short "why you might click" explanation between
// userID and targetProfileID.
func (s *Service) MatchBlurb(ctx context.Context, userID, targetProfileID string) (MatchBlurbResponse, error) {
	if !s.client.Configured() {
		return MatchBlurbResponse{}, ErrNotConfigured
	}

	me, target, err := s.loadPair(ctx, userID, targetProfileID)
	if err != nil {
		return MatchBlurbResponse{}, err
	}

	prompt := fmt.Sprintf(
		"In 1-2 warm, specific sentences, explain why these two people might get along, based on what's "+
			"actually in their profiles (shared interests, complementary traits, etc). Avoid generic filler.\n\n"+
			"Person A:\n%s\n\nPerson B:\n%s",
		describeProfile(me), describeProfile(target),
	)

	reply, err := s.client.Complete(ctx, []groq.Message{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: prompt},
	})
	if err != nil {
		return MatchBlurbResponse{}, err
	}
	return MatchBlurbResponse{Blurb: strings.TrimSpace(reply)}, nil
}

func (s *Service) loadPair(ctx context.Context, userID, targetProfileID string) (profiles.Profile, profiles.Profile, error) {
	me, err := s.profilesRepo.GetByUserID(ctx, userID)
	if err != nil {
		return profiles.Profile{}, profiles.Profile{}, err
	}
	target, err := s.profilesRepo.GetByID(ctx, targetProfileID)
	if err != nil {
		return profiles.Profile{}, profiles.Profile{}, err
	}
	return me, target, nil
}

func toResponse(m Message) MessageResponse {
	return MessageResponse{
		ID:        m.ID,
		Role:      m.Role,
		Content:   m.Content,
		CreatedAt: m.CreatedAt.Format(time.RFC3339),
	}
}

func describeName(p profiles.Profile) string {
	if p.FullName != nil {
		return *p.FullName
	}
	return "this person"
}

func describeProfile(p profiles.Profile) string {
	var parts []string
	add := func(label string, v *string) {
		if v != nil && *v != "" {
			parts = append(parts, label+": "+*v)
		}
	}
	if p.FullName != nil {
		parts = append(parts, "Name: "+*p.FullName)
	}
	if p.DateOfBirth != nil {
		age := int(time.Since(*p.DateOfBirth).Hours() / 24 / 365.25)
		parts = append(parts, fmt.Sprintf("Age: %d", age))
	}
	add("City", p.City)
	add("Religion", p.Religion)
	add("Education", p.Education)
	add("Occupation", p.Occupation)
	add("About", p.AboutMe)
	if len(p.Hobbies) > 0 {
		parts = append(parts, "Hobbies: "+strings.Join(p.Hobbies, ", "))
	}
	if len(parts) == 0 {
		return "(no details available)"
	}
	return strings.Join(parts, "\n")
}

// extractJSON trims any stray text a model adds around a JSON array
// despite being asked not to (e.g. "Here you go: [...]").
func extractJSON(s string) string {
	start := strings.Index(s, "[")
	end := strings.LastIndex(s, "]")
	if start == -1 || end == -1 || end < start {
		return s
	}
	return s[start : end+1]
}

func splitFallback(s string) []string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		l = strings.TrimSpace(strings.TrimLeft(l, "-*0123456789. "))
		if l != "" {
			out = append(out, l)
		}
	}
	if len(out) == 0 {
		return []string{s}
	}
	return out
}
