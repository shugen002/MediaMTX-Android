enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  badRequest,
  server,
  parse,
  unsupported,
  unknown,
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.kind = ApiErrorKind.unknown,
    this.statusCode,
    this.detail,
  });

  final String message;
  final ApiErrorKind kind;
  final int? statusCode;
  final String? detail;

  bool get isAuthError =>
      kind == ApiErrorKind.unauthorized || kind == ApiErrorKind.forbidden;

  bool get isOffline =>
      kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  String get friendlyMessage {
    if (detail != null && detail!.trim().isNotEmpty) {
      return '$message\n${detail!.trim()}';
    }
    return message;
  }

  factory ApiException.fromStatus(int status, String? serverMessage) {
    final detail = serverMessage?.trim();
    return switch (status) {
      400 => ApiException(
        '请求参数不正确',
        kind: ApiErrorKind.badRequest,
        statusCode: status,
        detail: detail,
      ),
      401 => ApiException(
        '认证失败，请检查用户名和密码',
        kind: ApiErrorKind.unauthorized,
        statusCode: status,
        detail: detail,
      ),
      403 => ApiException(
        '当前账号没有该操作权限',
        kind: ApiErrorKind.forbidden,
        statusCode: status,
        detail: detail,
      ),
      404 => ApiException(
        '接口或资源不存在',
        kind: ApiErrorKind.notFound,
        statusCode: status,
        detail: detail,
      ),
      405 => ApiException(
        '服务器不支持该操作',
        kind: ApiErrorKind.unsupported,
        statusCode: status,
        detail: detail,
      ),
      _ =>
        status >= 500
            ? ApiException(
                'MediaMTX 服务端返回错误（$status）',
                kind: ApiErrorKind.server,
                statusCode: status,
                detail: detail,
              )
            : ApiException(
                '请求失败（$status）',
                kind: ApiErrorKind.unknown,
                statusCode: status,
                detail: detail,
              ),
    };
  }

  @override
  String toString() => friendlyMessage;
}
