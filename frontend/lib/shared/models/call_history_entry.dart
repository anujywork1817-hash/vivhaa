/// From the current user's point of view — matches whichever side of
/// call_sessions.caller_user_id/callee_user_id the current user was on.
enum CallDirection { outgoing, incoming }

/// Mirrors call_sessions.status (see
/// backend/migrations/000023_create_call_sessions.up.sql):
/// initiated: ringing, not yet answered
/// ongoing:   answered, currently connected (shouldn't really appear in
///            history — a finished call is always completed/missed/etc —
///            but handled defensively)
/// completed: was ongoing, ended normally by either side
/// missed:    never answered (30s timeout) or caller cancelled first
/// rejected:  callee explicitly declined
/// failed:    connection/ICE failure after being ongoing
enum CallStatusHistory { initiated, ongoing, completed, missed, rejected, failed }

class CallHistoryEntry {
  final String id;
  final String partnerUserId;
  final String partnerName;
  final String? partnerPhoto;
  final CallDirection direction;
  final CallStatusHistory status;
  final bool isVideo;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final String? endReason;

  const CallHistoryEntry({
    required this.id,
    required this.partnerUserId,
    required this.partnerName,
    this.partnerPhoto,
    required this.direction,
    required this.status,
    required this.isVideo,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
    this.endReason,
  });

  factory CallHistoryEntry.fromJson(Map<String, dynamic> json) {
    return CallHistoryEntry(
      id: json['id'] as String,
      partnerUserId: json['partner_user_id'] as String,
      partnerName: (json['partner_name'] as String?) ?? 'Someone',
      partnerPhoto: json['partner_photo'] as String?,
      direction: (json['direction'] as String?) == 'incoming'
          ? CallDirection.incoming
          : CallDirection.outgoing,
      status: CallStatusHistory.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => CallStatusHistory.completed,
      ),
      isVideo: (json['is_video'] as bool?) ?? true,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt:
          json['ended_at'] != null ? DateTime.parse(json['ended_at'] as String) : null,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      endReason: json['end_reason'] as String?,
    );
  }
}
