import 'package:dio/dio.dart';
import '../exceptions/app_exception.dart';

/// Converts a DioException into the app's typed [AppFailure], reading the
/// backend's `{success:false, error:{code, message, details}}` envelope
/// when present. Every Api*Repository should route its catch block
/// through this so screens see one consistent failure shape regardless
/// of which endpoint failed.
AppFailure mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return AppFailure.timeout();
    case DioExceptionType.connectionError:
      return AppFailure.network();
    default:
      break;
  }

  final status = e.response?.statusCode;
  final body = e.response?.data;
  final message = _extractMessage(body);
  final fieldErrors = _extractFieldErrors(body);

  switch (status) {
    case 400:
    case 422:
      return AppFailure.validation(message ?? 'That input isn\'t valid.', fieldErrors);
    case 401:
      return AppFailure.unauthorized(message);
    case 403:
      return AppFailure(
        type: AppFailureType.forbidden,
        message: message ?? 'You don\'t have access to do that.',
      );
    case 404:
      return AppFailure(
        type: AppFailureType.notFound,
        message: message ?? 'That couldn\'t be found.',
      );
    case null:
      return AppFailure.network();
    default:
      if (status >= 500) return AppFailure.server(message);
      return AppFailure.unknown(message);
  }
}

String? _extractMessage(dynamic body) {
  if (body is Map && body['error'] is Map) {
    final msg = body['error']['message'];
    if (msg is String) return msg;
  }
  return null;
}

Map<String, String>? _extractFieldErrors(dynamic body) {
  if (body is! Map || body['error'] is! Map) return null;
  final details = body['error']['details'];
  if (details is! List) return null;

  final out = <String, String>{};
  for (final entry in details) {
    if (entry is Map && entry['field'] is String && entry['message'] is String) {
      out[entry['field'] as String] = entry['message'] as String;
    }
  }
  return out.isEmpty ? null : out;
}
