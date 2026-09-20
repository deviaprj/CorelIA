import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_role.dart';

/// Profil utilisateur minimal.
class AppUser {
  const AppUser({
    required this.uid,
    required this.createdAt,
    this.email,
    this.displayName,
    this.photoURL,
    this.role = UserRole.free,
    this.totalRequests = 0,
  });

  final String uid;
  final DateTime createdAt;
  final String? email;
  final String? displayName;
  final String? photoURL;
  final UserRole role;
  final int totalRequests;

  bool get isFull => role.isFull;

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      email: data['email'] as String?,
      displayName: data['displayName'] as String?,
      photoURL: data['photoURL'] as String?,
      role: UserRole.fromId(data['plan'] as String? ?? data['role'] as String?),
      totalRequests: data['totalRequests'] as int? ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoURL': photoURL,
        'plan': role.id,
        'totalRequests': totalRequests,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  AppUser copyWith({
    String? displayName,
    String? photoURL,
    UserRole? role,
    int? totalRequests,
  }) =>
      AppUser(
        uid: uid,
        createdAt: createdAt,
        email: email,
        displayName: displayName ?? this.displayName,
        photoURL: photoURL ?? this.photoURL,
        role: role ?? this.role,
        totalRequests: totalRequests ?? this.totalRequests,
      );
}
