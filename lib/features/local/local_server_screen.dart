import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/local/local_server_controller.dart';
import '../../data/models/local_server_models.dart';
import '../../state/app_state.dart';
import 'local_logs_screen.dart';

class LocalServerScreen extends StatefulWidget {
  const LocalServerScreen({super.key});

  @override
  State<LocalServerScreen> createState() => _LocalServerScreenState();
}

class _LocalServerScreenState extends State<LocalServerScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final local = context.read<LocalServerController>();
      if (!local.initialized) await local.initialize();
      await local.refreshStatus();
      await local.loadLogs();
      if (local.latest == null) unawaited(local.checkLatest());
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        if (local.phase == LocalPhase.running || local.isRunning) {
          local.refreshStatus();
          local.loadLogs();
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<LocalServerController>().refreshBatteryOptimizationStatus();
    }
  }

  Future<void> _connect() async {
    final local = context.read<LocalServerController>();
    final app = context.read<AppState>();
    final credentials = local.credentials;
    if (credentials == null) {
      showAppSnack(context, 'API 凭据尚未生成，请重新启动本机服务', error: true);
      return;
    }
    setState(() => _connecting = true);
    final ok = await app.connectToLocalServer(
      baseUrl: local.apiBaseUrl,
      username: credentials.user,
      secret: credentials.pass,
    );
    if (!mounted) return;
    setState(() => _connecting = false);
    if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      showAppSnack(context, app.error ?? '无法连接本机 API，请查看日志', error: true);
    }
  }

  Future<void> _downloadAndStart({bool update = false}) async {
    final local = context.read<LocalServerController>();
    final ok = await local.downloadAndStart();
    if (!mounted) return;
    if (ok) {
      await local.loadLogs();
      if (!mounted) return;
      showAppSnack(context, update ? '已更新并启动' : 'MediaMTX 已启动');
      await _connect();
    } else if (local.error != null) {
      showAppSnack(context, local.error!, error: true);
    }
  }

  Future<void> _start() async {
    final local = context.read<LocalServerController>();
    final ok = await local.start();
    if (!mounted) return;
    if (ok) {
      await local.loadLogs();
      if (!mounted) return;
      await _connect();
    } else if (local.error != null) {
      showAppSnack(context, local.error!, error: true);
    }
  }

  Future<void> _stop() async {
    final local = context.read<LocalServerController>();
    await local.stop();
    if (!mounted) return;
    showAppSnack(context, '本机服务已停止');
  }

  Future<void> _uninstall() async {
    final local = context.read<LocalServerController>();
    final app = context.read<AppState>();
    final confirmed = await showConfirmDialog(
      context,
      title: '卸载本机 MediaMTX？',
      message: '将停止服务并删除已下载的二进制、配置和本机保存的 API 账号。',
      confirmLabel: '卸载',
      destructive: true,
    );
    if (!confirmed) return;
    if (app.active?.isLocal == true) {
      await app.disconnect();
    }
    await local.uninstall();
    if (!mounted) return;
    showAppSnack(context, '已卸载');
  }

  void _openLogs() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LocalLogsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final local = context.watch<LocalServerController>();
    final colors = context.colors;
    final running = local.phase == LocalPhase.running || local.isRunning;
    final installed = local.install != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本机服务'),
        actions: [
          IconButton(
            onPressed: () async {
              await local.refreshStatus();
              await local.loadLogs();
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
          if (installed)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'uninstall') _uninstall();
                if (value == 'logs') _openLogs();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'logs',
                  child: Row(
                    children: [
                      Icon(Icons.article_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('查看日志'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'uninstall',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('卸载'),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackdrop(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 34),
          child: ContentWidth(
            maxWidth: 1600,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!local.supported) ...[
                  _UnsupportedCard(),
                  const SizedBox(height: 16),
                ] else ...[
                  _StatusHero(
                    local: local,
                    running: running,
                    installed: installed,
                    connecting: _connecting,
                    onPrimary: () {
                      if (running) {
                        _connect();
                      } else if (installed) {
                        _start();
                      } else {
                        _downloadAndStart();
                      }
                    },
                    onStop: running ? _stop : null,
                    onRestart: running ? () => local.restart() : null,
                    onUpdate: local.updateAvailable
                        ? () => _downloadAndStart(update: true)
                        : null,
                  ),
                  if (local.error != null) ...[
                    const SizedBox(height: 12),
                    ErrorBanner(
                      message: local.error!,
                      onClose: local.clearError,
                      onRetry: local.isRunning
                          ? null
                          : local.install == null
                          ? () => _downloadAndStart()
                          : () => local.start(),
                    ),
                  ],
                  if (local.phase == LocalPhase.downloading ||
                      local.phase == LocalPhase.installing ||
                      local.phase == LocalPhase.starting) ...[
                    const SizedBox(height: 12),
                    _ProgressCard(local: local),
                  ],
                  const SizedBox(height: 14),
                  _VersionCard(local: local),
                  const SizedBox(height: 14),
                  _BackgroundProtectionCard(local: local),
                  const SizedBox(height: 14),
                  _PortsCard(local: local),
                  const SizedBox(height: 14),
                  _LogsCard(local: local, onOpen: _openLogs),
                  const SizedBox(height: 14),
                  _FilesCard(local: local),
                  const SizedBox(height: 14),
                  const _InfoCard(),
                  const SizedBox(height: 16),
                  if (installed) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: local.isRunning ? _stop : null,
                            icon: const Icon(Icons.stop_rounded, size: 18),
                            label: const Text('停止服务'),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _downloadAndStart(update: true),
                            icon: const Icon(
                              Icons.system_update_rounded,
                              size: 18,
                            ),
                            label: const Text('重装最新版'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _uninstall,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.danger,
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 17,
                        ),
                        label: const Text('卸载本机服务'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnsupportedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            Icons.devices_other_rounded,
            size: 40,
            color: context.colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            '本机运行仅支持 Android',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '当前平台无法启动 MediaMTX 进程，但服务器连接与管理功能仍然可用。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.local,
    required this.running,
    required this.installed,
    required this.connecting,
    required this.onPrimary,
    required this.onStop,
    required this.onRestart,
    required this.onUpdate,
  });

  final LocalServerController local;
  final bool running;
  final bool installed;
  final bool connecting;
  final VoidCallback onPrimary;
  final VoidCallback? onStop;
  final VoidCallback? onRestart;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final accent = running
        ? colors.success
        : local.phase == LocalPhase.error
        ? colors.danger
        : Theme.of(context).colorScheme.primary;
    final gradient = running
        ? const [Color(0xFF0E3B2D), Color(0xFF0A1A16)]
        : const [Color(0xFF14263E), Color(0xFF0B1421)];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(
                label: running
                    ? 'RUNNING'
                    : installed
                    ? 'INSTALLED'
                    : 'NOT INSTALLED',
                color: running ? const Color(0xFF43E6B4) : Colors.white70,
                pulse: running,
                dense: true,
              ),
              const Spacer(),
              Icon(
                Icons.smartphone_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            running
                ? '本机 MediaMTX 正在运行'
                : installed
                ? '本机 MediaMTX 已安装'
                : '在手机上运行 MediaMTX',
            style: textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            running
                ? '${local.installedVersion} · API 127.0.0.1:${local.ports.api}'
                : installed
                ? '${local.installedVersion} · 点击启动以开始推流'
                : '下载最新官方版本，直接在设备上启动推流服务',
            style: textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.58),
            ),
          ),
          if (running) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _HeroMeta(label: '模式', value: '前台服务'),
                const SizedBox(width: 26),
                _HeroMeta(label: 'API', value: '${local.ports.api}'),
                const SizedBox(width: 26),
                _HeroMeta(label: '版本', value: local.installedVersion),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed:
                      connecting ||
                          local.busy ||
                          local.phase == LocalPhase.downloading
                      ? null
                      : onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: running
                        ? const Color(0xFF43E6B4)
                        : Theme.of(context).colorScheme.primary,
                    foregroundColor: running
                        ? const Color(0xFF002117)
                        : Colors.white,
                    disabledBackgroundColor: Colors.white.withValues(
                      alpha: 0.12,
                    ),
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.72,
                    ),
                  ),
                  icon: connecting
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          running
                              ? Icons.link_rounded
                              : installed
                              ? Icons.play_arrow_rounded
                              : Icons.download_rounded,
                          size: 19,
                        ),
                  label: Text(
                    connecting
                        ? '连接中'
                        : local.phase == LocalPhase.downloading
                        ? '正在下载…'
                        : local.phase == LocalPhase.installing
                        ? '正在安装…'
                        : local.phase == LocalPhase.starting
                        ? '正在启动…'
                        : running
                        ? '连接并管理'
                        : installed
                        ? '启动服务'
                        : '下载并启动',
                  ),
                ),
              ),
              if (onStop != null) ...[
                const SizedBox(width: 8),
                IconAction(
                  icon: Icons.stop_rounded,
                  tooltip: '停止',
                  onPressed: onStop!,
                  color: Colors.white,
                ),
              ],
              if (onRestart != null) ...[
                const SizedBox(width: 8),
                IconAction(
                  icon: Icons.restart_alt_rounded,
                  tooltip: '重启',
                  onPressed: onRestart!,
                  color: Colors.white,
                ),
              ],
            ],
          ),
          if (onUpdate != null) ...[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: local.busy ? null : onUpdate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFC66D),
                  side: const BorderSide(color: Color(0x66FFC66D)),
                ),
                icon: const Icon(Icons.system_update_alt_rounded, size: 17),
                label: Text('更新到 ${local.latestVersion}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 8.5,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.local});

  final LocalServerController local;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final downloading = local.phase == LocalPhase.downloading;
    final progress = local.progress.clamp(0.0, 1.0);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: downloading && local.totalBytes > 0 ? progress : null,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                local.phase.label,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (downloading && local.totalBytes > 0)
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: downloading && local.totalBytes > 0 ? progress : null,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                downloading
                    ? '${formatBytes(local.receivedBytes)} / ${local.totalBytes > 0 ? formatBytes(local.totalBytes) : '未知大小'}'
                    : '正在校验与安装，请稍候…',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const Spacer(),
              if (downloading)
                GestureDetector(
                  onTap: local.cancelDownload,
                  child: Text(
                    '取消',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.local});

  final LocalServerController local;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 19,
                color: colors.chartIn,
              ),
              const SizedBox(width: 9),
              Text(
                '版本',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: local.phase == LocalPhase.checking
                    ? null
                    : () => local.checkLatest(force: true),
                child: local.phase == LocalPhase.checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('检查更新'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _VersionValue(
                  label: '已安装',
                  value: local.installedVersion,
                ),
              ),
              Container(width: 1, height: 30, color: colors.border),
              Expanded(
                child: _VersionValue(
                  label: '最新版本',
                  value: local.latestVersion,
                  accent: local.updateAvailable ? colors.warning : null,
                ),
              ),
            ],
          ),
          if (local.latestError != null) ...[
            const SizedBox(height: 8),
            Text(
              local.latestError!,
              style: textTheme.labelSmall?.copyWith(
                color: colors.warning,
                fontSize: 9.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VersionValue extends StatelessWidget {
  const _VersionValue({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.textTertiary, fontSize: 9),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 13,
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundProtectionCard extends StatelessWidget {
  const _BackgroundProtectionCard({required this.local});

  final LocalServerController local;

  Future<void> _showHelp(BuildContext context) async {
    const commands =
        'adb shell settings put global settings_enable_monitor_phantom_procs false\n'
        '# Android 13 及以上如仍被清理：\n'
        'adb shell device_config set_sync_disabled_for_tests persistent\n'
        'adb shell device_config put activity_manager max_phantom_processes 2147483647';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('后台服务被系统清理？'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Android 12+ 会清理应用启动的子进程（Phantom Process Killer），前台服务也可能被冻结或终止。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 10),
              Text(
                '华为/小米/OPPO 还需在系统设置中允许「自启动」和「后台活动」，并关闭电池优化。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 12),
              Text(
                '一次性 ADB 豁免（重启后仍生效）：',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              const CodeBlock(code: commands, maxHeight: 190),
              const SizedBox(height: 8),
              Text(
                '这些命令只关闭系统的子进程清理，不修改系统分区。没有电脑 ADB 时，可先尝试加入电池白名单并锁定后台。',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(height: 1.55),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => copyText(context, commands),
            child: const Text('复制命令'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final protected = local.ignoringBatteryOptimizations;
    final accent = protected ? colors.success : colors.warning;
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      borderColor: accent.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                protected ? Icons.shield_rounded : Icons.battery_alert_rounded,
                size: 19,
                color: accent,
              ),
              const SizedBox(width: 9),
              Text(
                '后台运行保护',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              StatusPill(
                label: protected ? '已加入白名单' : '可能被清理',
                color: accent,
                dense: true,
              ),
              const SizedBox(width: 2),
              IconButton(
                onPressed: () => _showHelp(context),
                icon: Icon(
                  Icons.help_outline_rounded,
                  size: 17,
                  color: colors.textTertiary,
                ),
                tooltip: '后台被杀怎么办？',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            protected
                ? '系统已允许应用在后台持续运行。华为/小米等机型建议同时在「应用启动管理」中允许自启动和后台活动。'
                : '华为、小米、OPPO 等系统可能在锁屏或切换后台后冻结进程。建议加入电池优化白名单，并在系统设置中允许自启动。',
            style: textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontSize: 10.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              if (!protected)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        local.requestBatteryOptimizationExemption(),
                    icon: const Icon(Icons.battery_saver_rounded, size: 17),
                    label: const Text('加入白名单'),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => local.refreshBatteryOptimizationStatus(),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('检测状态'),
                  ),
                ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: local.openAppSettings,
                child: const Text('应用设置'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PortsCard extends StatelessWidget {
  const _PortsCard({required this.local});

  final LocalServerController local;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 15),
          childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
          iconColor: colors.textTertiary,
          collapsedIconColor: colors.textTertiary,
          leading: Icon(Icons.settings_ethernet_rounded, color: colors.warning),
          title: Text(
            '端口设置',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'API ${local.ports.api} · RTSP ${local.ports.rtsp} · RTMP ${local.ports.rtmp}',
            style: textTheme.labelSmall?.copyWith(
              color: colors.textTertiary,
              fontSize: 9.5,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '修改端口会重写配置；服务运行时会自动重启。',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontSize: 10.5,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _editPorts(context, local),
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('编辑端口'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPorts(
    BuildContext context,
    LocalServerController local,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PortsSheet(local: local),
    );
  }
}

class _PortsSheet extends StatefulWidget {
  const _PortsSheet({required this.local});

  final LocalServerController local;

  @override
  State<_PortsSheet> createState() => _PortsSheetState();
}

class _PortsSheetState extends State<_PortsSheet> {
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ports = widget.local.ports;
    _controllers = {
      'api': TextEditingController(text: '${ports.api}'),
      'rtsp': TextEditingController(text: '${ports.rtsp}'),
      'rtp': TextEditingController(text: '${ports.rtp}'),
      'rtcp': TextEditingController(text: '${ports.rtcp}'),
      'rtmp': TextEditingController(text: '${ports.rtmp}'),
      'hls': TextEditingController(text: '${ports.hls}'),
      'webrtc': TextEditingController(text: '${ports.webrtc}'),
      'webrtcUdp': TextEditingController(text: '${ports.webrtcUdp}'),
      'srt': TextEditingController(text: '${ports.srt}'),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int _value(String key) => int.tryParse(_controllers[key]!.text.trim()) ?? 0;

  Future<void> _apply() async {
    final ports = LocalServerPorts(
      api: _value('api'),
      rtsp: _value('rtsp'),
      rtp: _value('rtp'),
      rtcp: _value('rtcp'),
      rtmp: _value('rtmp'),
      hls: _value('hls'),
      webrtc: _value('webrtc'),
      webrtcUdp: _value('webrtcUdp'),
      srt: _value('srt'),
    );
    final validation = ports.validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.local.savePorts(ports);
      if (!mounted) return;
      showAppSnack(context, '端口设置已保存');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final fields = const [
      ('api', 'API', 'Control API，App 管理入口'),
      ('rtsp', 'RTSP', 'TCP 推流/播放'),
      ('rtp', 'RTP', 'UDP RTP 端口'),
      ('rtcp', 'RTCP', 'UDP RTCP 端口'),
      ('rtmp', 'RTMP', 'TCP 推流/播放'),
      ('hls', 'HLS', 'HTTP 播放'),
      ('webrtc', 'WebRTC', 'HTTP 信令'),
      ('webrtcUdp', 'WebRTC ICE', 'UDP ICE'),
      ('srt', 'SRT', 'UDP 推流/播放'),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '端口设置',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '确保这些端口未被其他应用占用，且在局域网内可访问。',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < fields.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fields[i].$2,
                            style: textTheme.titleSmall?.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            fields[i].$3,
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _controllers[fields[i].$1],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (i < fields.length - 1) const SizedBox(height: 8),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(color: colors.danger),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _apply,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存并应用'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogsCard extends StatelessWidget {
  const _LogsCard({required this.local, required this.onOpen});

  final LocalServerController local;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final lines = local.logs
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final preview = lines.length > 8
        ? lines.sublist(lines.length - 8).join('\n')
        : lines.join('\n');
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal_rounded, size: 18, color: colors.chartOut),
              const SizedBox(width: 8),
              Text(
                '服务日志',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(onPressed: onOpen, child: const Text('全部')),
            ],
          ),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.isDark
                  ? const Color(0xFF070B10)
                  : const Color(0xFFF0F4FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: SingleChildScrollView(
              child: Text(
                preview.isEmpty ? '暂无日志，启动服务后会在这里显示。' : preview,
                style: textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  height: 1.55,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesCard extends StatelessWidget {
  const _FilesCard({required this.local});

  final LocalServerController local;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open_rounded, size: 18, color: colors.info),
              const SizedBox(width: 8),
              Text(
                '文件与导出',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '系统文件选择器中的「MTX 控制台」可浏览日志、录制和版本文件；手动替换 mediamtx 二进制前请先停止服务。',
            style: textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontSize: 10.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: local.install == null
                      ? null
                      : () async {
                          try {
                            await local.openDocuments();
                          } catch (error) {
                            if (context.mounted) {
                              showAppSnack(
                                context,
                                '无法打开文件管理器：$error',
                                error: true,
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.drive_file_move_outline, size: 17),
                  label: const Text('打开文件'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: local.install == null
                      ? null
                      : () async {
                          try {
                            await local.shareLog();
                          } catch (error) {
                            if (context.mounted) {
                              showAppSnack(context, '导出失败：$error', error: true);
                            }
                          }
                        },
                  icon: const Icon(Icons.ios_share_rounded, size: 17),
                  label: const Text('导出日志'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: colors.info),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '本机服务绑定 0.0.0.0，同一局域网内的设备可推流；Control API 使用随机密码保护。'
              '服务由前台通知保活，锁屏后仍会继续运行。',
              style: textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontSize: 10.5,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
