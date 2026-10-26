import 'dart:math' as math;

import 'package:intl/intl.dart';

final NumberFormat _integer = NumberFormat.decimalPattern('zh_CN');
final DateFormat _time = DateFormat('HH:mm:ss');
final DateFormat _dateTime = DateFormat('yyyy-MM-dd HH:mm');
final DateFormat _shortDate = DateFormat('MM-dd HH:mm');

String formatInt(num value) => _integer.format(value);

String formatBytes(num value, {int decimals = 1}) {
  if (value.isNaN || value.isInfinite || value <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var size = value.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  if (unit == 0) return '${size.toStringAsFixed(0)} B';
  final digits = size >= 100 ? 0 : decimals;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}

String formatRate(num bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 bps';
  final bits = bytesPerSecond * 8;
  if (bits < 1000) return '${bits.toStringAsFixed(0)} bps';
  if (bits < 1000 * 1000) return '${(bits / 1000).toStringAsFixed(0)} Kbps';
  if (bits < 1000 * 1000 * 1000) {
    return '${(bits / 1000000).toStringAsFixed(bits < 10000000 ? 1 : 0)} Mbps';
  }
  return '${(bits / 1000000000).toStringAsFixed(2)} Gbps';
}

String formatUptime(Duration duration) {
  if (duration.inSeconds < 0) return '—';
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (days > 0) {
    return '$days 天 $hours 小时';
  }
  if (hours > 0) return '$hours 小时 $minutes 分';
  if (minutes > 0) return '$minutes 分 $seconds 秒';
  return '$seconds 秒';
}

String formatDurationShort(Duration duration) {
  if (duration.inSeconds < 60) return '${duration.inSeconds}s';
  if (duration.inMinutes < 60) return '${duration.inMinutes}m';
  if (duration.inHours < 24) {
    return '${duration.inHours}h ${duration.inMinutes % 60}m';
  }
  return '${duration.inDays}d ${duration.inHours % 24}h';
}

String formatClock(DateTime time) => _time.format(time.toLocal());

String formatDateTime(DateTime time) => _dateTime.format(time.toLocal());

String formatShortDate(DateTime time) => _shortDate.format(time.toLocal());

String relativeTime(DateTime? time) {
  if (time == null) return '—';
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 45) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return _shortDate.format(time.toLocal());
}

String compactCount(int value) {
  if (value < 1000) return '$value';
  if (value < 10000) return '${(value / 1000).toStringAsFixed(1)}k';
  if (value < 1000000) return '${(value / 10000).toStringAsFixed(1)}w';
  return '${(value / 1000000).toStringAsFixed(1)}m';
}

String percent(num value, {int decimals = 0}) {
  if (value.isNaN || value.isInfinite) return '—';
  return '${(value * 100).toStringAsFixed(decimals)}%';
}

String durationBetween(DateTime? start, [DateTime? end]) {
  if (start == null) return '—';
  final value = (end ?? DateTime.now()).difference(start);
  return formatDurationShort(value);
}

double niceMax(double value) {
  if (value <= 0) return 1;
  final magnitude = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final normalized = value / magnitude;
  final step = normalized <= 1
      ? 1
      : normalized <= 2
      ? 2
      : normalized <= 5
      ? 5
      : 10;
  return step * magnitude;
}

String truncateMiddle(String value, {int max = 34}) {
  if (value.length <= max) return value;
  final half = (max - 1) ~/ 2;
  return '${value.substring(0, half)}…${value.substring(value.length - half)}';
}
