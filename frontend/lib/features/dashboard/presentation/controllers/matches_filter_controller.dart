import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MatchesFilter { newMembers, all, nearby }

final matchesFilterProvider = StateProvider<MatchesFilter>((ref) => MatchesFilter.all);
