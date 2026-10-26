import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createHttpClient({
  bool allowBadCertificates = false,
  Duration timeout = const Duration(seconds: 12),
}) {
  final inner = HttpClient()..connectionTimeout = timeout;
  if (allowBadCertificates) {
    inner.badCertificateCallback = (_, _, _) => true;
  }
  return IOClient(inner);
}
