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

  Future<void> _switchServer() async {
    final app = context.read<AppState>();
    final selected = await showModalBottomSheet<ServerProfile>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ServerSheet(
        servers: app.servers,
        active: app.active,
        onAdd: () {
          Navigator.pop(context);
          _addServer();
        },
        onSettings: () {
          Navigator.pop(context);
          _editServer();
        },
      ),
    );
    if (selected == null || !mounted) return;
    if (selected.id == app.active?.id) return;
    final ok = await app.connect(selected);
    if (!mounted) return;
    if (!ok) showAppSnack(context, app.error ?? '连接失败', error: true);
  }

  Future<void> _addServer() async {
    final app = context.read<AppState>();
    final profile = await Navigator.of(context).push<ServerProfile>(
      MaterialPageRoute(builder: (_) => const ServerFormScreen()),
    );
    if (profile != null && mounted) {
      final ok = await app.connect(profile);
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

  Future<void> _disconnect() async {
    final app = context.read<AppState>();
    final confirmed = await showConfirmDialog(
      context,
      title: '断开连接？',
      message: '将返回服务器列表，本机保存的配置不会被删除。',
      confirmLabel: '断开',
    );
    if (confirmed) await app.disconnect();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        app.showServers();
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
                  online: app.isConnected,
                  connecting: app.status == ServerConnectionStatus.connecting,
                  onRefresh: _refresh,
                  onSwitch: _switchServer,
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
                  onDisconnect: _disconnect,
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
    required this.onSwitch,
    required this.onEdit,
    required this.onAdd,
    required this.onLocal,
    required this.onSettings,
    required this.onDisconnect,
  });

  final ServerProfile profile;
  final bool online;
  final bool connecting;
  final Future<void> Function() onRefresh;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onAdd;
  final VoidCallback onLocal;
  final VoidCallback onSettings;
  final VoidCallback onDisconnect;

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
              onTap: onSwitch,
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
                          Icons.unfold_more_rounded,
                          size: 14,
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
                                ? '${hostWithPort(profile)} · 在线'
                                : connecting
                                ? '正在连接…'
                                : '连接中断',
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
                case 'switch':
                  onSwitch();
                case 'edit':
                  onEdit();
                case 'add':
                  onAdd();
                case 'local':
                  onLocal();
                case 'settings':
                  onSettings();
                case 'disconnect':
                  onDisconnect();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'switch',
                child: _MenuRow(icon: Icons.swap_horiz_rounded, label: '切换服务器'),
              ),
              PopupMenuItem(
                value: 'edit',
                child: _MenuRow(icon: Icons.tune_rounded, label: '连接设置'),
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
              PopupMenuItem(
                value: 'disconnect',
                child: _MenuRow(icon: Icons.logout_rounded, label: '断开连接'),
              ),
            ],
          ),
        ],
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

class _ServerSheet extends StatelessWidget {
  const _ServerSheet({
    required this.servers,
    required this.active,
    required this.onAdd,
    required this.onSettings,
  });

  final List<ServerProfile> servers;
  final ServerProfile? active;
  final VoidCallback onAdd;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '切换服务器',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '连接另一个 MediaMTX 实例',
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: servers.map((server) {
                    final selected = server.id == active?.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(13),
                        onTap: () => Navigator.pop(context, server),
                        borderColor: selected
                            ? scheme.primary.withValues(alpha: 0.5)
                            : null,
                        child: Row(
                          children: [
                            Icon(
                              server.isLocal
                                  ? Icons.smartphone_rounded
                                  : Icons.dns_rounded,
                              size: 20,
                              color: selected
                                  ? scheme.primary
                                  : colors.textSecondary,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    server.displayName,
                                    style: textTheme.titleSmall,
                                  ),
                                  Text(
                                    server.baseUrl,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colors.textTertiary,
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: scheme.primary,
                                size: 19,
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('添加服务器'),
                  ),
                ),
                const SizedBox(width: 9),
                IconAction(
                  icon: Icons.settings_outlined,
                  tooltip: '当前连接设置',
                  onPressed: onSettings,
                ),
              ],
            ),
          ],
        ),
      ),
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
