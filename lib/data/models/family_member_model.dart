import '../../core/constants/app_constants.dart';

/// 家庭成员模型
class FamilyMemberModel {
  final String id;
  final String name;
  final String avatar;
  final FamilyRole role;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FamilyMemberModel({
    required this.id,
    required this.name,
    this.avatar = '',
    this.role = FamilyRole.owner,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FamilyMemberModel.fromJson(Map<String, dynamic> json) {
    return FamilyMemberModel(
      id: json['id'] as String,
      name: json['name'] as String,
      avatar: json['avatar'] as String? ?? '',
      role: FamilyRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => FamilyRole.other,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'role': role.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  FamilyMemberModel copyWith({
    String? id,
    String? name,
    String? avatar,
    FamilyRole? role,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FamilyMemberModel(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
