import '../../../core/api/api_result.dart';
import '../../../shared/models/ai_message.dart';

abstract class AiRepository {
  Future<ApiResult<List<AiMessage>>> getHistory();
  Future<ApiResult<AiMessage>> sendMessage(String text);
  Future<ApiResult<List<String>>> getIcebreakers(String profileId);
  Future<ApiResult<String>> getMatchBlurb(String profileId);
}
