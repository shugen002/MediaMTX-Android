class PathConfig {
  PathConfig({required this.name, required this.raw});

  final String name;
  final Map<String, dynamic> raw;

  String get source => (raw['source'] ?? '').toString();

  bool get alwaysAvailable => raw['alwaysAvailable'] == true;

  bool get record => raw['record'] == true;

  bool get sourceOnDemand => raw['sourceOnDemand'] == true;

  String? get runOnDemand {
    final value = (raw['runOnDemand'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  int get maxReaders {
    final value = raw['maxReaders'];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String get recordPath => (raw['recordPath'] ?? '').toString();

  List<String> get configuredKeys => raw.entries
      .where((entry) => entry.value != null)
      .map((entry) => entry.key)
      .toList(growable: false);

  PathConfig copyWith({Map<String, dynamic>? raw}) {
    return PathConfig(name: name, raw: raw ?? this.raw);
  }

  factory PathConfig.fromJson(Map<String, dynamic> json) {
    return PathConfig(
      name: (json['name'] ?? '').toString(),
      raw: Map<String, dynamic>.from(json)..remove('name'),
    );
  }
}
