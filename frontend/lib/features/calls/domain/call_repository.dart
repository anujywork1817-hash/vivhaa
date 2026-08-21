import '../../../core/api/api_result.dart';
import '../../../shared/models/call_history_entry.dart';

class IceServer {
  final List<String> urls;
  final String? username;
  final String? credential;

  const IceServer({required this.urls, this.username, this.credential});

  /// Shape flutter_webrtc's RTCPeerConnection config expects.
  Map<String, dynamic> toRtcConfig() => {
        'urls': urls,
        if (username != null) 'username': username,
        if (credential != null) 'credential': credential,
      };
}

abstract class CallRepository {
  /// GET /video-call/ice-servers — STUN + a freshly generated, time-limited
  /// TURN credential. Fetched fresh per call rather than cached, since a
  /// TURN credential expires.
  Future<ApiResult<List<IceServer>>> getIceServers();

  /// GET /calls/history — page is 0-based here (mirrors SearchRepository.search);
  /// the implementation adds 1 before sending it to the backend.
  Future<ApiResult<List<CallHistoryEntry>>> getCallHistory({int page = 0});
}
