import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 打开原生全屏播放器预览一路直播流。
///
/// 走 Android 原生 ExoPlayer + SurfaceView（见 PreviewPlayerActivity），
/// 这样解码器输出直接进原生窗口，硬件解码可用；Flutter 纹理路径在这台
/// 华为设备上会让 OMX 解码器初始化失败。
class PreviewPlayer {
  const PreviewPlayer._();

  static const _channel = MethodChannel('space.shugen.mediamtx/preview');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// [hlsUrl] / [rtspUrl] 至少提供一个，原生端按 HLS → RTSP 顺序尝试。
  static Future<void> open({
    required String title,
    String? hlsUrl,
    String? rtspUrl,
    String? subtitle,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('当前平台不支持内嵌预览');
    }
    await _channel.invokeMethod<bool>('open', {
      'title': title,
      'subtitle': subtitle,
      'hlsUrl': hlsUrl,
      'rtspUrl': rtspUrl,
    });
  }
}
