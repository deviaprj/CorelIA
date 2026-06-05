import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class Project {
  const Project({
    required this.id,
    required this.userId,
    required this.name,
    this.description = '',
    this.conversationIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String description;
  final List<String> conversationIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Project.create({
    required String userId,
    required String name,
    String description = '',
  }) {
    final now = DateTime.now();
    return Project(
      id: const Uuid().v4(),
      userId: userId,
      name: name,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Project.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Project(
      id: doc.id,
      userId: d['userId'] as String,
      name: d['name'] as String,
      description: (d['description'] as String?) ?? '',
      conversationIds: List<String>.from(
          (d['conversationIds'] as List?) ?? []),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      updatedAt: (d['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'name': name,
        'description': description,
        'conversationIds': conversationIds,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  Project copyWith({
    String? name,
    String? description,
    List<String>? conversationIds,
    DateTime? updatedAt,
  }) =>
      Project(
        id: id,
        userId: userId,
        name: name ?? this.name,
        description: description ?? this.description,
        conversationIds: conversationIds ?? this.conversationIds,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
