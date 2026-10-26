import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../data/models/session_info.dart';

IconData protocolIcon(SessionProtocol protocol) => switch (protocol) {
  SessionProtocol.rtsp => Icons.videocam_outlined,
  SessionProtocol.rtmp => Icons.cell_tower_rounded,
  SessionProtocol.srt => Icons.swap_vert_rounded,
  SessionProtocol.webrtc => Icons.language_rounded,
  SessionProtocol.hls => Icons.layers_outlined,
  SessionProtocol.moq => Icons.bolt_rounded,
};

Color protocolColor(SessionProtocol protocol, AppColors colors) =>
    switch (protocol) {
      SessionProtocol.rtsp => colors.chartIn,
      SessionProtocol.rtmp => colors.warning,
      SessionProtocol.srt => const Color(0xFFB48CFF),
      SessionProtocol.webrtc => colors.success,
      SessionProtocol.hls => colors.danger,
      SessionProtocol.moq => const Color(0xFF4ED4E8),
    };
