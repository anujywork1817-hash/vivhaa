import '../../../core/api/api_result.dart';
import '../../../shared/models/visitor_record.dart';

abstract class VisitorRepository {
  Future<ApiResult<List<VisitorRecord>>> getVisitors();
}
