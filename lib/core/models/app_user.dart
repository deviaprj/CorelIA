import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_role.dart';

/// Profil utilisateur.
class AppUser {
  const AppUser({
    required this.uid,
    required this.createdAt,
    this.email,
    this.displayName,
    this.firstName,
    this.lastName,
    this.birthDate,
    this.photoURL,
    this.role = UserRole.free,
    this.totalRequests = 0,
  });

  final String uid;
  final DateTime createdAt;
  final String? email;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final DateTime? birthDate;
  final String? photoURL;
  final UserRole role;
  final int totalRequests;

  bool get isFull => role.isFull;

  /// Nom affichable : « Prénom Nom », sinon le pseudonyme, sinon l'e-mail.
  String get label {
    final full = [firstName, lastName]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (full.isNotEmpty) return full;
    final pseudo = displayName?.trim();
    if (pseudo != null && pseudo.isNotEmpty) return pseudo;
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail.split('@').first;
    return 'Utilisateur';
  }

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      email: data['email'] as String?,
      displayName: data['displayName'] as String?,
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      birthDate: (data['birthDate'] as Timestamp?)?.toDate(),
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
        'firstName': firstName,
        'lastName': lastName,
        if (birthDate != null) 'birthDate': Timestamp.fromDate(birthDate!),
        'photoURL': photoURL,
        'plan': role.id,
        'totalRequests': totalRequests,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  AppUser copyWith({
    String? displayName,
    String? firstName,
    String? lastName,
    DateTime? birthDate,
    String? photoURL,
    UserRole? role,
    int? totalRequests,
  }) =>
      AppUser(
        uid: uid,
        createdAt: createdAt,
        email: email,
        displayName: displayName ?? this.displayName,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        birthDate: birthDate ?? this.birthDate,
        photoURL: photoURL ?? this.photoURL,
        role: role ?? this.role,
        totalRequests: totalRequests ?? this.totalRequests,
      );
}
