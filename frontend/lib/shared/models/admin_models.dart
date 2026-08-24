class AdminUser {
  final String id;
  final String? phone;
  final String? email;
  final bool phoneVerified;
  final bool emailVerified;
  final String status;
  final String role;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  const AdminUser({
    required this.id,
    this.phone,
    this.email,
    required this.phoneVerified,
    required this.emailVerified,
    required this.status,
    required this.role,
    this.lastLoginAt,
    required this.createdAt,
  });
}

class AdminDashboardStats {
  final int totalUsers;
  final int activeUsers;
  final int suspendedUsers;
  final int newSignupsToday;
  final int totalMatches;
  final int totalMessages;
  final int pendingVerifications;
  final int pendingReports;
  final int activeSubscriptions;
  final int revenueInr;

  const AdminDashboardStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.suspendedUsers,
    required this.newSignupsToday,
    required this.totalMatches,
    required this.totalMessages,
    required this.pendingVerifications,
    required this.pendingReports,
    required this.activeSubscriptions,
    required this.revenueInr,
  });
}

class AdminVerificationRequest {
  final String id;
  final String userId;
  final String documentType;
  final String documentUrl;
  final String status;
  final DateTime createdAt;

  const AdminVerificationRequest({
    required this.id,
    required this.userId,
    required this.documentType,
    required this.documentUrl,
    required this.status,
    required this.createdAt,
  });
}

class AdminReport {
  final String id;
  final String reporterUserId;
  final String reportedUserId;
  final String? reporterName;
  final String? reportedName;
  final String reason;
  final String reasonLabel;
  final String? details;
  final String category;
  final String priority;
  final String status;
  final DateTime createdAt;

  const AdminReport({
    required this.id,
    required this.reporterUserId,
    required this.reportedUserId,
    this.reporterName,
    this.reportedName,
    required this.reason,
    required this.reasonLabel,
    this.details,
    required this.category,
    required this.priority,
    required this.status,
    required this.createdAt,
  });
}
