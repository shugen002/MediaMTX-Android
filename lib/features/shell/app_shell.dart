import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/url_utils.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../data/local/local_server_controller.dart';
import '../../data/models/server_profile.dart';
import '../../state/app_state.dart';
import '../dashboard/dashboard_screen.dart';
import '../local/local_server_screen.dart';
import '../manage/manage_screen.dart';
import '../paths/paths_screen.dart';
import '../servers/server_form_screen.dart';
import '../servers/servers_screen.dart';
import '../sessions/sessions_screen.dart';
import '../settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  LocalServerController? _localEvents;
  int _lastLocalEvent = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final local = context.read<LocalServerController>();
      _localEvents = local;
      _lastLocalEvent = local.eventRevision;
      local.addListener(_onLocalEvent);
      _maybePromptBatteryProtection(local);
    });
  }

  @override
  void dispose() {
    _localEvents?.removeListener(_onLocalEvent);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLocalEvent() {
    final local = _localEvents;
    if (!mounted || local == null) return;
    if (local.eventRevision == _lastLocalEvent) return;
    _lastLocalEvent = local.eventRevision;
    final event = local.lastEvent;
    if (event == null) return;
    final app = context.read<AppState>();
    app.refresh(silent: true, withSessions: true);
    showAppSnack(context, event);
  }

  Future<void> _maybePromptBatteryProtection(
    LocalServerController local,
  ) async {
    final app = context.read<AppState>();
    if (app.active?.isLocal != true || local.install == null) return;
    if (local.ignoringBatteryOptimizations) return;
    final shouldPrompt = await local.consumeBatteryPrompt();
    if (!mounted || !shouldPrompt) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.battery_alert_rounded),
        title: const Text('避免后台服务被清理'),
        content: const Text(
          'Android 12+ 和部分华为/小米系统会清理后台进程，即使有前台通知。'
          '建议将 MTX 控制台加入电池优化白名单，并在系统设置中允许自启动和后台活动。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (go == true) await local.requestBatteryOptimizationExemption();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final app = context.read<AppState>();
      final local = _localEvents;
      if (local != null) {
        unawaited(local.resetEventBaseline());
        unawaited(local.refreshBatteryOptimizationStatus());
      }
      if (app.active != null) app.refresh(silent: true, withSessions: true);
    }
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    await app.refresh(withSessions: true);
  }

  Future<void> _addServer() async {
    final app = context.read<AppState>();
    final profile = await Navigator.of(context).push<ServerProfile>(
      MaterialPageRoute(builder: (_) => const ServerFormScreen()),
    );
    if (profile != null && mounted) {
      final ok = await app.openServer(profile);
      if (!ok && mounted) {
        showAppSnack(context, app.error ?? '连接失败', error: true);
      }
    }
  }

  void _editServer() {
    final app = context.read<AppState>();
    final profile = app.active;
    if (profile == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ServerFormScreen(profile: profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = context.colors;
    final profile = app.active;
    if (profile == null) return const ServersScreen();

    final pages = [
      DashboardScreen(onNavigate: (index) => setState(() => _index = index)),
      const PathsScreen(),
      const SessionsScreen(),
      const ManageScreen(),
    ];

    if (app.snapshot == null) {
      return _OpeningScaffold(
        profile: profile,
        error: app.status == ApiStatus.loading ? null : app.error,
        onRetry: () => app.openServer(profile),
        onClose: app.closeActiveServer,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 返回即关闭这台服务器的面板，回到服务器列表。
        app.closeActiveServer();
      },
      child: Scaffold(
        extendBody: true,
        body: AppBackdrop(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _ShellHeader(
                  profile: profile,
                  online: app.isApiReady,
                  connecting: app.status == ApiStatus.loading,
                  onRefresh: _refresh,
                  onEdit: _editServer,
                  onAdd: _addServer,
                  onLocal: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LocalServerScreen(),
                    ),
                  ),
                  onSettings: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  onClose: app.closeActiveServer,
                ),
                Expanded(
                  child: IndexedStack(index: _index, children: pages),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _FloatingNav(
          index: _index,
          onSelected: (index) => setState(() => _index = index),
          color: colors.surface,
        ),
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.profile,
    required this.online,
    required this.connecting,
    required this.onRefresh,
    required this.onEdit,
    required this.onAdd,
    required this.onLocal,
    required this.onSettings,
    required this.onClose,
  });

  final ServerProfile profile;
  final bool online;
  final bool connecting;
  final Future<void> Function() onRefresh;
  final VoidCallback onEdit;
  final VoidCallback onAdd;
  final VoidCallback onLocal;
  final VoidCallback onSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = connecting
        ? Theme.of(context).colorScheme.primary
        : online
        ? colors.success
        : colors.danger;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 4),
      child: Row(
        children: [
          const BrandMark(size: 35),
          const SizedBox(width: 11),
          Expanded(
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 11,
                          color: colors.textTertiary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        StatusDot(color: statusColor, size: 5, pulse: online),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            online
                                ? '${hostWithPort(profile)} · API 正常'
                                : connecting
                                ? '正在读取…'
                                : '无法访问该服务器',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (connecting)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconAction(
              icon: Icons.refresh_rounded,
              tooltip: '刷新',
              size: 36,
              onPressed: onRefresh,
            ),
          const SizedBox(width: 7),
          PopupMenuButton<String>(
            tooltip: '菜单',
            icon: Icon(
              Icons.more_horiz_rounded,
              color: colors.textSecondary,
              size: 22,
            ),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                case 'add':
                  onAdd();
                case 'local':
                  onLocal();
                case 'settings':
                  onSettings();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: _MenuRow(icon: Icons.tune_rounded, label: '服务器设置'),
              ),
              PopupMenuItem(
                value: 'local',
                child: _MenuRow(icon: Icons.smartphone_rounded, label: '本机服务'),
              ),
              PopupMenuItem(
                value: 'add',
                child: _MenuRow(icon: Icons.add_rounded, label: '添加服务器'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'settings',
                child: _MenuRow(icon: Icons.settings_outlined, label: '偏好设置'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpeningScaffold extends StatelessWidget {
  const _OpeningScaffold({
    required this.profile,
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  final ServerProfile profile;
  final String? error;
  final Future<void> Function() onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconAction(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '返回服务器列表',
                      onPressed: onClose,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      profile.displayName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (error == null)
                          const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        else
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 34,
                            color: colors.textTertiary,
                          ),
                        const SizedBox(height: 14),
                        Text(
                          error ?? '正在读取 ${profile.displayName}…',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: error == null
                                ? colors.textSecondary
                                : colors.danger,
                            height: 1.5,
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton.icon(
                                onPressed: () => onRetry(),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text('重试'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed: onClose,
                                child: const Text('返回列表'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.index,
    required this.onSelected,
    required this.color,
  });

  final int index;
  final ValueChanged<int> onSelected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final items = const [
      (icon: Icons.grid_view_rounded, label: '概览'),
      (icon: Icons.route_rounded, label: '路径'),
      (icon: Icons.bolt_rounded, label: '会话'),
      (icon: Icons.tune_rounded, label: '管理'),
    ];
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: colors.isDark ? 0.35 : 0.08,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => onSelected(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: i == index
                                  ? scheme.primary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              items[i].icon,
                              size: 21,
                              color: i == index
                                  ? scheme.primary
                                  : colors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            items[i].label,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontSize: 9.5,
                                  color: i == index
                                      ? scheme.primary
                                      : colors.textTertiary,
                                  fontWeight: i == index
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
