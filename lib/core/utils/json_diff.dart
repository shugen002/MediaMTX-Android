import 'dart:convert';

/// Returns only the top-level keys whose values differ between [before] and
/// [after]. Removed keys are ignored: MediaMTX's PATCH semantics are safer when
/// the client never sends a field it did not explicitly change.
Map<String, dynamic> changedTopLevelKeys(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  final result = <String, dynamic>{};
  for (final entry in after.entries) {
    final previous = before[entry.key];
    if (jsonEncode(previous) != jsonEncode(entry.value)) {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

/// Detects server-redacted secrets inside a config patch. Sending these back
/// would overwrite the real credentials with the literal `<redacted>`.
bool containsRedactedSecret(dynamic value) {
  if (value is String) return value.contains('<redacted>');
  if (value is Map) {
    return value.values.any(containsRedactedSecret);
  }
  if (value is Iterable) return value.any(containsRedactedSecret);
  return false;
}
