import 'dart:math';

enum ServerAuthMethod { none, basic, bearer }

extension ServerAuthMethodX on ServerAuthMethod {
  String get label => switch (this) {
    ServerAuthMethod.none => '无需认证',
    ServerAuthMethod.basic => '用户名 / 密码',
    ServerAuthMethod.bearer => 'Bearer Token',
  };

  String get storageValue => name;

  static ServerAuthMethod fromStorage(String? value) {
    return ServerAuthMethod.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ServerAuthMethod.none,
    );
  }
}

class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.createdAt,
    this.username = '',
    this.authMethod = ServerAuthMethod.none,
    this.isLocal = false,
    this.allowSelfSigned = false,
    this.lastConnectedAt,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final ServerAuthMethod authMethod;
  final bool isLocal;
  final bool allowSelfSigned;
  final DateTime createdAt;
  final DateTime? lastConnectedAt;

  String get displayName => name.trim().isEmpty ? baseUrl : name.trim();

  ServerProfile copyWith({
    String? name,
    String? baseUrl,
    String? username,
    ServerAuthMethod? authMethod,
    bool? isLocal,
    bool? allowSelfSigned,
    DateTime? lastConnectedAt,
  }) {
    return ServerProfile(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      isLocal: isLocal ?? this.isLocal,
      allowSelfSigned: allowSelfSigned ?? this.allowSelfSigned,
      createdAt: createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'username': username,
    'authMethod': authMethod.name,
    'isLocal': isLocal,
    'allowSelfSigned': allowSelfSigned,
    'createdAt': createdAt.toIso8601String(),
    'lastConnectedAt': lastConnectedAt?.toIso8601String(),
  };

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      authMethod: ServerAuthMethodX.fromStorage(json['authMethod'] as String?),
      isLocal: json['isLocal'] == true,
      allowSelfSigned: json['allowSelfSigned'] == true,
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      lastConnectedAt: DateTime.tryParse(
        (json['lastConnectedAt'] ?? '').toString(),
      ),
    );
  }

  static String newId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(0xFFFFFF);
    return '${now.toRadixString(36)}${random.toRadixString(36)}';
  }
}

class ServerSecret {
  const ServerSecret({required this.value, this.username = ''});

  final String value;
  final String username;
}
