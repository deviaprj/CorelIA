import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoURL;
  final String plan; // 'free' | 'pro'
  final int dailyRequests;
  final String? dailyRequestsDate; // ISO date yyyy-MM-dd
  final int totalRequests;
  final DateTime createdAt;
  final String? referralCode;
  final String? referredBy;

  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoURL,
    this.plan = 'free',
    this.dailyRequests = 0,
    this.dailyRequestsDate,
    this.totalRequests = 0,
    required this.createdAt,
    this.referralCode,
    this.referredBy,
  });

  bool get isPro => plan == 'pro';

  /// Daily request limit: -1 for pro (unlimited), 20 for free
  int get dailyRequestsLimit => isPro ? -1 : 20;

  int get remainingRequests {
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (dailyRequestsDate != today) return 20;
    return (20 - dailyRequests).clamp(0, 20);
  }

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      email: data['email'] as String?,
      displayName: data['displayName'] as String?,
      photoURL: data['photoURL'] as String?,
      plan: (data['plan'] as String?) ?? 'free',
      dailyRequests: (data['dailyRequests'] as int?) ?? 0,
      dailyRequestsDate: data['dailyRequestsDate'] as String?,
      totalRequests: (data['totalRequests'] as int?) ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      referralCode: data['referralCode'] as String?,
      referredBy: data['referredBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoURL': photoURL,
        'plan': plan,
        'dailyRequests': dailyRequests,
        'dailyRequestsDate': dailyRequestsDate,
        'totalRequests': totalRequests,
        'createdAt': Timestamp.fromDate(createdAt),
        'referralCode': referralCode,
        'referredBy': referredBy,
      };

  AppUser copyWith({
    String? plan,
    int? dailyRequests,
    String? dailyRequestsDate,
    int? totalRequests,
    String? displayName,
    String? photoURL,
  }) =>
      AppUser(
        uid: uid,
        email: email,
        displayName: displayName ?? this.displayName,
        photoURL: photoURL ?? this.photoURL,
        plan: plan ?? this.plan,
        dailyRequests: dailyRequests ?? this.dailyRequests,
        dailyRequestsDate: dailyRequestsDate ?? this.dailyRequestsDate,
        totalRequests: totalRequests ?? this.totalRequests,
        createdAt: createdAt,
        referralCode: referralCode,
        referredBy: referredBy,
      );
}
