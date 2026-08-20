import '../../../core/api/api_result.dart';
import '../../../shared/models/partner_preferences.dart';

abstract class PreferencesRepository {
  Future<ApiResult<void>> upsert(PartnerPreferences preferences);
}
