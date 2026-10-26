import 'package:http/http.dart' as http;

http.Client createHttpClient({
  bool allowBadCertificates = false,
  Duration timeout = const Duration(seconds: 12),
}) {
  return http.Client();
}
