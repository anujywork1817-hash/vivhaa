package calls

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"

	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/interests"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/queue"
	appwebsocket "matrimony-backend/internal/websocket"
)

// ringTimeout is how long a callee has to answer before the call is
// auto-cancelled as missed — matches the 30s the frontend's incoming-call
// screen auto-dismisses at, so both sides agree on when a call gives up.
const ringTimeout = 30 * time.Second

// sweepInterval is how often each instance checks for calls that have
// been ringing past ringTimeout (see runRingTimeoutSweep) — the
// cross-instance replacement for the old per-call *time.Timer. The
// worst-case delay before a timed-out call is actually finalized is one
// sweepInterval, not instant, which is unnoticeable against the 30s ring
// window itself.
const sweepInterval = 5 * time.Second

const (
	defaultLimit = 20
	maxLimit     = 100
)

// Config carries the ICE server settings that come from env vars —
// separated from the constructor's other (dependency) args since these
// are plain values, not collaborators.
type Config struct {
	StunURLs   []string
	TURNURL    string
	TURNSecret string
}

// Service used to keep live call coordination state (who's in which call,
// whether it's connected, the ring-timeout timer) in local Go maps — fine
// with one process, broken with more than one (BUG-C08): a call created
// on instance A is invisible to instance B, which is exactly where the
// callee's WS connection might be. That state now lives in Postgres
// (call_sessions + active_calls_by_user, see repository.go), which every
// instance reads/writes, so it no longer matters which instance handles
// which side of a call's signaling.
type Service struct {
	repo          *Repository
	interestsRepo *interests.Repository
	blockedRepo   *blocked.Repository
	profilesRepo  *profiles.Repository
	hub           *appwebsocket.Hub
	publisher     *queue.Publisher
	cfg           Config
}

func NewService(repo *Repository, interestsRepo *interests.Repository, blockedRepo *blocked.Repository, profilesRepo *profiles.Repository, hub *appwebsocket.Hub, publisher *queue.Publisher, cfg Config) *Service {
	s := &Service{
		repo: repo, interestsRepo: interestsRepo, blockedRepo: blockedRepo, profilesRepo: profilesRepo, hub: hub, publisher: publisher, cfg: cfg,
	}
	// Runs for the process lifetime, same as Hub's background loops —
	// there's no general shutdown-hook mechanism for background work in
	// this codebase (cmd/scheduler's ticker loop is the same pattern).
	go s.runRingTimeoutSweep(context.Background())
	return s
}

func (s *Service) pushEvent(userID, eventType string, data any) {
	payload, err := json.Marshal(map[string]any{"type": eventType, "data": data})
	if err != nil {
		slog.Error("calls: failed to marshal outgoing WS event", "event_type", eventType, "error", err)
		return
	}
	s.hub.SendToUser(userID, payload)
}

// notifyMissedCall sends a real push notification (FCM, via the same
// pipeline chat/interests already use) so a callee whose app has no live
// WebSocket connection — closed/killed, not just backgrounded — still
// finds out someone tried to reach them. Calling is WebSocket-only: with
// no connection there is no way to make the device actually ring, so
// this can't recreate a real incoming-call screen while the app is
// dead, only tell them afterward, the same way a missed call works on
// a phone that was off.
func (s *Service) notifyMissedCall(ctx context.Context, calleeUserID, callerName string) {
	_ = s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
		UserID: calleeUserID,
		Type:   "missed_call",
		Title:  "Missed call",
		Body:   callerName + " tried to call you",
		Data:   map[string]any{"caller_name": callerName},
	})
}

func (s *Service) callerDisplayName(ctx context.Context, callerUserID string) string {
	if p, err := s.profilesRepo.GetByUserID(ctx, callerUserID); err == nil && p.FullName != nil && *p.FullName != "" {
		return *p.FullName
	}
	return "Someone"
}

// ICEServers returns the caller's STUN + TURN server list, with a fresh
// time-limited TURN credential generated just for them — the frontend
// never hardcodes or caches a TURN secret.
func (s *Service) ICEServers(userID string) ICEServersResponse {
	urls := s.cfg.StunURLs
	if len(urls) == 0 {
		urls = []string{"stun:stun.l.google.com:19302"}
	}
	servers := []ICEServer{{URLs: urls}}

	if s.cfg.TURNURL != "" && s.cfg.TURNSecret != "" {
		username, credential := generateTURNCredentials(s.cfg.TURNSecret, userID, turnCredentialTTL)
		servers = append(servers, ICEServer{
			URLs:       []string{s.cfg.TURNURL},
			Username:   username,
			Credential: credential,
		})
	}
	return ICEServersResponse{ICEServers: servers}
}

// HandleIncoming parses and dispatches one call:* message. Errors are
// reported back to the sender as an "error" event rather than silently
// dropped — a caller staring at a spinner with no explanation is exactly
// what this is meant to avoid.
func (s *Service) HandleIncoming(ctx context.Context, userID string, raw []byte) {
	var in IncomingCallMessage
	if err := json.Unmarshal(raw, &in); err != nil {
		s.pushEvent(userID, "error", map[string]string{"message": "invalid call payload"})
		return
	}

	switch in.Type {
	case "call:initiate":
		s.initiate(ctx, userID, in)
	case "call:accept":
		s.accept(ctx, userID, in)
	case "call:reject":
		s.reject(ctx, userID, in)
	case "call:ice-candidate":
		s.relayICE(ctx, userID, in)
	case "call:renegotiate-offer":
		s.relayRenegotiateOffer(ctx, userID, in)
	case "call:renegotiate-answer":
		s.relayRenegotiateAnswer(ctx, userID, in)
	case "call:end":
		s.end(ctx, userID, in)
	default:
		s.pushEvent(userID, "error", map[string]string{"message": "unknown call event"})
	}
}

// HandleDisconnect ends whatever call userID is in, if any, when their
// socket connection drops without an explicit call:end — otherwise the
// other party's call would ring or sit "connected" forever with no signal
// that anything went wrong (a killed app, a lost network, etc.). Fires
// with no request-scoped ctx (the connection has already closed by the
// time this runs), so like Service.finish this reaches for
// context.Background() directly.
func (s *Service) HandleDisconnect(userID string) {
	ctx := context.Background()
	call, err := s.repo.GetActiveForUser(ctx, userID)
	if err != nil {
		return // not in a call, or a transient lookup error — nothing to clean up either way
	}

	other := otherParty(call, userID)
	status, reason := "missed", "caller_cancelled"
	if call.Status == "ongoing" {
		status, reason = "failed", "connection_lost"
	}
	s.pushEvent(other, "call:end", map[string]string{"call_id": call.ID, "reason": reason})
	s.finish(ctx, call.ID, status, reason)
}

func (s *Service) initiate(ctx context.Context, callerUserID string, in IncomingCallMessage) {
	calleeUserID := in.CalleeID
	if calleeUserID == "" || len(in.Offer) == 0 {
		s.pushEvent(callerUserID, "error", map[string]string{"message": "callee_id and offer are required"})
		return
	}
	if calleeUserID == callerUserID {
		s.pushEvent(callerUserID, "error", map[string]string{"message": "cannot call yourself"})
		return
	}

	// Reuse the exact same "are these two mutually connected" rule chat
	// already enforces for messaging (interests.Repository.IsAccepted),
	// so calling and chatting always agree on who you can reach.
	connected, err := s.interestsRepo.IsAccepted(ctx, callerUserID, calleeUserID)
	if err != nil {
		s.pushEvent(callerUserID, "error", map[string]string{"message": "something went wrong"})
		return
	}
	if !connected {
		s.pushEvent(callerUserID, "error", map[string]string{"message": "you can only call a mutual match"})
		return
	}

	isBlocked, err := s.blockedRepo.IsBlocked(ctx, callerUserID, calleeUserID)
	if err != nil {
		s.pushEvent(callerUserID, "error", map[string]string{"message": "something went wrong"})
		return
	}
	if isBlocked {
		s.pushEvent(callerUserID, "error", map[string]string{"message": "you can't call this member"})
		return
	}

	if !s.hub.IsOnline(ctx, calleeUserID) {
		s.pushEvent(callerUserID, "error", map[string]string{"message": "this member is currently offline"})
		// The callee's app has no live connection to ring on — see
		// notifyMissedCall's doc comment. At least let them find out.
		s.notifyMissedCall(ctx, calleeUserID, s.callerDisplayName(ctx, callerUserID))
		return
	}

	// Every call before this field existed was a video call, so a missing
	// is_video (nil) defaults to true rather than false's zero value.
	isVideo := true
	if in.IsVideo != nil {
		isVideo = *in.IsVideo
	}

	callID := uuid.NewString()
	_, err = s.repo.Create(ctx, callID, callerUserID, calleeUserID, isVideo)
	switch {
	case errors.Is(err, ErrBusy):
		// ErrBusy doesn't say which of the two participants it was — a
		// quick lookup on the caller disambiguates which outward signal
		// to send: the caller themselves being busy is a plain error,
		// the callee being busy is call:busy (lets the client show
		// "they're on another call" instead of a generic failure).
		if _, callerErr := s.repo.GetActiveForUser(ctx, callerUserID); callerErr == nil {
			s.pushEvent(callerUserID, "error", map[string]string{"message": "you're already on a call"})
			return
		}
		s.pushEvent(callerUserID, "call:busy", map[string]string{"callee_id": calleeUserID})
		return
	case err != nil:
		s.pushEvent(callerUserID, "error", map[string]string{"message": "something went wrong"})
		return
	}

	callerName := s.callerDisplayName(ctx, callerUserID)

	s.pushEvent(calleeUserID, "call:incoming", map[string]any{
		"call_id":     callID,
		"caller_id":   callerUserID,
		"caller_name": callerName,
		"is_video":    isVideo,
		"offer":       in.Offer,
	})

	// The callee learns callID from call:incoming; the caller otherwise
	// never learns their own call's ID at all until call:accept arrives —
	// leaving a window (offer sent, not yet answered) where the caller's
	// own trickling ICE candidates have no call_id to attach to and are
	// silently unroutable. Ack the caller immediately with the same ID.
	s.pushEvent(callerUserID, "call:ringing", map[string]any{"call_id": callID})
}

func (s *Service) accept(ctx context.Context, calleeUserID string, in IncomingCallMessage) {
	call, ok := s.getActiveCallFor(ctx, calleeUserID, in.CallID)
	if !ok || call.CalleeUserID != calleeUserID {
		s.pushEvent(calleeUserID, "error", map[string]string{"message": "call not found"})
		return
	}

	if err := s.repo.MarkOngoing(ctx, call.ID); err != nil {
		s.pushEvent(calleeUserID, "error", map[string]string{"message": "something went wrong"})
		return
	}

	s.pushEvent(call.CallerUserID, "call:accept", map[string]any{"call_id": call.ID, "answer": in.Answer})
}

func (s *Service) reject(ctx context.Context, userID string, in IncomingCallMessage) {
	call, ok := s.getActiveCallFor(ctx, userID, in.CallID)
	if !ok || call.CalleeUserID != userID {
		return
	}
	s.pushEvent(call.CallerUserID, "call:reject", map[string]string{"call_id": call.ID})
	s.finish(ctx, call.ID, "rejected", "rejected")
}

func (s *Service) relayICE(ctx context.Context, userID string, in IncomingCallMessage) {
	call, ok := s.getActiveCallFor(ctx, userID, in.CallID)
	if !ok {
		return
	}
	// The client-supplied TargetUserID field was previously trusted as-is:
	// a call only ever has two participants, so there is never a
	// legitimate reason to relay to anyone but the other one — always
	// deriving it server-side (ignoring whatever the client sent) closes
	// an IDOR where a participant could redirect call:ice-candidate
	// (network/ICE metadata) to an arbitrary third party who never
	// consented to be part of the call.
	target := otherParty(call, userID)
	s.pushEvent(target, "call:ice-candidate", map[string]any{
		"call_id":      call.ID,
		"from_user_id": userID,
		"candidate":    in.Candidate,
	})
}

// relayRenegotiateOffer and relayRenegotiateAnswer relay a mid-call
// ICE-restart offer/answer to the other party — same "server doesn't
// understand WebRTC payloads, just forwards them" role as relayICE, but
// for a fresh SDP exchange instead of a trickled candidate. Only the
// call's caller is expected to send a renegotiate-offer (see
// CallController._attemptIceRestart on the client — one side driving
// restarts avoids both sides racing to renegotiate at once), but the
// server doesn't need to enforce that; it just relays whatever it's
// handed to whoever isn't the sender.
func (s *Service) relayRenegotiateOffer(ctx context.Context, userID string, in IncomingCallMessage) {
	call, ok := s.getActiveCallFor(ctx, userID, in.CallID)
	if !ok || len(in.Offer) == 0 {
		return
	}
	s.pushEvent(otherParty(call, userID), "call:renegotiate-offer", map[string]any{
		"call_id": call.ID,
		"offer":   in.Offer,
	})
}

func (s *Service) relayRenegotiateAnswer(ctx context.Context, userID string, in IncomingCallMessage) {
	call, ok := s.getActiveCallFor(ctx, userID, in.CallID)
	if !ok || len(in.Answer) == 0 {
		return
	}
	s.pushEvent(otherParty(call, userID), "call:renegotiate-answer", map[string]any{
		"call_id": call.ID,
		"answer":  in.Answer,
	})
}

func (s *Service) end(ctx context.Context, userID string, in IncomingCallMessage) {
	call, ok := s.getActiveCallFor(ctx, userID, in.CallID)
	if !ok {
		return
	}
	other := otherParty(call, userID)

	var status, reason string
	switch {
	case in.Reason == "connection_failed":
		status, reason = "failed", "connection_failed"
	case call.Status != "ongoing":
		status, reason = "missed", "caller_cancelled"
	case userID == call.CallerUserID:
		status, reason = "completed", "caller_ended"
	default:
		status, reason = "completed", "callee_ended"
	}

	s.pushEvent(other, "call:end", map[string]string{"call_id": call.ID, "reason": reason})
	s.finish(ctx, call.ID, status, reason)
}

// runRingTimeoutSweep periodically finalizes calls that have been ringing
// past ringTimeout — see SweepExpiredRinging's doc for why this replaces
// the old per-call *time.Timer.
func (s *Service) runRingTimeoutSweep(ctx context.Context) {
	ticker := time.NewTicker(sweepInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.sweepOnce(ctx)
		}
	}
}

func (s *Service) sweepOnce(ctx context.Context) {
	swept, err := s.repo.SweepExpiredRinging(ctx, ringTimeout)
	if err != nil {
		return // transient DB error — the next tick tries again
	}
	for _, call := range swept {
		s.pushEvent(call.CallerUserID, "call:timeout", map[string]string{"call_id": call.ID})
		s.pushEvent(call.CalleeUserID, "call:timeout", map[string]string{"call_id": call.ID})
		// Unlike the offline-callee case in initiate(), the callee here
		// DID have a live connection when the call started (IsOnline
		// passed) but never answered within ringTimeout — could be a
		// closed app that dropped its socket mid-ring, could be a
		// genuinely missed ring. Either way, a missed-call notification
		// is the right outcome, same as every other calling app.
		s.notifyMissedCall(ctx, call.CalleeUserID, s.callerDisplayName(ctx, call.CallerUserID))
	}
}

func (s *Service) finish(ctx context.Context, callID, status, reason string) {
	_ = s.repo.End(ctx, callID, status, reason)
}

// getActiveCallFor mirrors what the old in-memory calls map's presence
// used to mean: a call exists, userID is one of its two participants, and
// it hasn't already ended. A call's row now survives past its end (for
// admin history), so "gone from the map" had to become an explicit
// status check instead of a lookup miss.
func (s *Service) getActiveCallFor(ctx context.Context, userID, callID string) (CallSession, bool) {
	call, err := s.repo.GetByID(ctx, callID)
	if err != nil {
		return CallSession{}, false
	}
	if call.CallerUserID != userID && call.CalleeUserID != userID {
		return CallSession{}, false
	}
	switch call.Status {
	case "completed", "missed", "rejected", "failed":
		return CallSession{}, false
	}
	return call, true
}

func otherParty(call CallSession, userID string) string {
	if call.CallerUserID == userID {
		return call.CalleeUserID
	}
	return call.CallerUserID
}

// IsCallType reports whether a raw inbound WS frame is a call:* message
// (vs. a legacy flat chat message, which has no "type" field at all) —
// used by chat.WSHandler to route one shared connection's messages to
// either chat.Service or calls.Service without either package needing to
// parse the other's payload shape.
func IsCallType(raw []byte) bool {
	var probe struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(raw, &probe); err != nil {
		return false
	}
	return strings.HasPrefix(probe.Type, "call:")
}

// ListMyCallHistory backs GET /calls/history — the caller's own past
// calls (as either caller or callee), newest first.
func (s *Service) ListMyCallHistory(ctx context.Context, userID string, page, limit int) ([]MyCallHistoryResponse, ListMeta, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = defaultLimit
	}
	if limit > maxLimit {
		limit = maxLimit
	}

	rows, total, err := s.repo.ListForUser(ctx, userID, page, limit)
	if err != nil {
		return nil, ListMeta{}, err
	}

	out := make([]MyCallHistoryResponse, 0, len(rows))
	for _, r := range rows {
		var endedAt *string
		if r.EndedAt != nil {
			v := r.EndedAt.Format(time.RFC3339)
			endedAt = &v
		}
		direction := "outgoing"
		partnerUserID := r.CalleeUserID
		if r.CallerUserID != userID {
			direction = "incoming"
			partnerUserID = r.CallerUserID
		}
		out = append(out, MyCallHistoryResponse{
			ID: r.ID, PartnerUserID: partnerUserID, PartnerName: r.PartnerName, PartnerPhoto: r.PartnerPhoto,
			Direction: direction, Status: r.Status, IsVideo: r.IsVideo,
			StartedAt: r.StartedAt.Format(time.RFC3339), EndedAt: endedAt,
			DurationSeconds: r.DurationSeconds, EndReason: r.EndReason,
		})
	}
	return out, ListMeta{Page: page, Limit: limit, Total: total}, nil
}

func (s *Service) AdminListCallHistory(ctx context.Context, f ListFilter) ([]CallHistoryResponse, ListMeta, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.Limit < 1 {
		f.Limit = defaultLimit
	}
	if f.Limit > maxLimit {
		f.Limit = maxLimit
	}

	rows, total, err := s.repo.ListForAdmin(ctx, f)
	if err != nil {
		return nil, ListMeta{}, err
	}

	out := make([]CallHistoryResponse, 0, len(rows))
	for _, r := range rows {
		var endedAt *string
		if r.EndedAt != nil {
			v := r.EndedAt.Format(time.RFC3339)
			endedAt = &v
		}
		out = append(out, CallHistoryResponse{
			ID: r.ID, CallerUserID: r.CallerUserID, CallerName: r.CallerName,
			CalleeUserID: r.CalleeUserID, CalleeName: r.CalleeName,
			Status: r.Status, IsVideo: r.IsVideo, StartedAt: r.StartedAt.Format(time.RFC3339), EndedAt: endedAt,
			DurationSeconds: r.DurationSeconds, EndReason: r.EndReason,
		})
	}
	return out, ListMeta{Page: f.Page, Limit: f.Limit, Total: total}, nil
}
