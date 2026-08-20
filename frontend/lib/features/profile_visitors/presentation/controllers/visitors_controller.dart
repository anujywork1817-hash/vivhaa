import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/visitor_record.dart';
import '../../data/api_visitor_repository.dart';

final visitorsListProvider = FutureProvider.autoDispose<List<VisitorRecord>>((ref) async {
  final result = await ref.watch(visitorRepositoryProvider).getVisitors();
  return result.when(success: (data) => data, failure: (f) => throw f);
});
