import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../data/local/local_server_controller.dart';
import '../../data/models/server_profile.dart';
import '../../state/app_state.dart';
import '../local/local_server_screen.dart';
import '../settings/settings_screen.dart';
import 'server_form_screen.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  /// 服务器列表是根页面，返回键即退出应用。本机服务在跑时先问一句：
  /// 是停止服务再退出，还是留在后台继续跑。
  Future<void> _handleExit(BuildContext context) async {
    final local = context.read<LocalServerController>();
    if (!local.isRunning) {
      await SystemNavigator.pop();
      return;
    }
    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.power_settings_new_rounded),
        title: const Text('退出 MTX 控制台？'),
        content: const Text(
          '本机 MediaMTX 正在运行。选择「保持后台运行」后应用会退出，'
          '服务继续在后台运行，可以随时从通知栏停止它。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitChoice.background),
            child: const Text('保持后台运行'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ExitChoice.stop),
            child: const Text('停止服务并退出'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == _ExitChoice.stop) {
      // stop() 内部会同时关掉「打开应用时自动运行」。
      await local.stop();
    }
    if (!context.mounted) return;
    await SystemNavigator.pop();
  }

  Future<void> _openForm(BuildContext context, {ServerProfile? profile}) async {
    final app = context.read<AppState>();
    final result = await Navigator.of(context).push<ServerProfile>(
      MaterialPageRoute(builder: (_) => ServerFormScreen(profile: profile)),
    );
    if (result != null) {
      await app.openServer(result);
    }
  }

  /// 打开一台服务器的面板。不做任何隐式动作：不会顺手拉起本机服务，
  /// 打开失败就在面板里显示错误并提供重试。
  Future<void> _openServer(BuildContext context, ServerProfile profile) async {
    final app = context.read<AppState>();
    await app.openServer(profile);
  }

  Future<void> _delete(BuildContext context, ServerProfile profile) async {
    final app = context.read<AppState>();
    final confirmed = await showConfirmDialog(
      context,
      title: '删除服务器？',
      message: '将移除「${profile.displayName}」及其本地保存的凭据，不会影响服务端。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    await app.deleteServer(profile);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final local = context.watch<LocalServerController>();
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // 服务器列表是应用的根页面：返回键退出应用（本机服务在跑时先问一句），
    // 不再回跳到会话界面，否则会在「会话」和「服务器列表」之间来回切换。
    // 想回到面板直接点当前服务器的卡片即可。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_handleExit(context));
      },
      child: Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: local.refreshStatus,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    sliver: SliverFillRemaining(
                      hasScrollBody: false,
                      child: ContentWidth(
                        maxWidth: 1600,
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const BrandLockup(logoSize: 40),
                                const Spacer(),
                                IconAction(
                                  icon: Icons.tune_rounded,
                                  tooltip: '设置',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 38),
                            const TechLabel('MEDIA CONTROL / 001'),
                            const SizedBox(height: 12),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '把流媒体服务\n'),
                                  TextSpan(
                                    text: '装进口袋',
                                    style: TextStyle(
                                      color: scheme.primary,
                                      shadows: [
                                        Shadow(
                                          color: scheme.primary.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 24,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              style: textTheme.displayMedium?.copyWith(
                                fontSize: 38,
                                height: 1.12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.6,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Text(
                                '连接 MediaMTX，实时掌控路径、会话和服务配置；也可以在手机上下载并运行最新的服务端。',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.65,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _openForm(context),
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 20,
                                    ),
                                    label: const Text('添加服务器'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const LocalServerScreen(),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.rocket_launch_outlined,
                                      size: 19,
                                    ),
                                    label: const Text('本机运行'),
                                  ),
                                ),
                              ],
                            ),
                            if (local.supported &&
                                (local.install != null ||
                                    local.phase == LocalPhase.running)) ...[
                              const SizedBox(height: 16),
                              _LocalRuntimeCard(local: local),
                            ],
                            if (app.error != null && app.snapshot == null) ...[
                              const SizedBox(height: 18),
                              ErrorBanner(
                                message: app.error!,
                                onClose: app.clearError,
                              ),
                            ],
                            if (app.servers.isEmpty) ...[
                              const SizedBox(height: 26),
                              _GettingStarted(
                                onAdd: () => _openForm(context),
                                onLocal: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const LocalServerScreen(),
                                  ),
                                ),
                              ),
                            ] else ...[
                              SectionHeader(
                                title: '我的服务器',
                                subtitle: '${app.servers.length} 个已保存的服务器',
                                padding: const EdgeInsets.fromLTRB(
                                  2,
                                  30,
                                  2,
                                  12,
                                ),
                              ),
                              ...app.servers.map((server) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 11),
                                  child: _ServerCard(
                                    profile: server,
                                    onTap: () => _openServer(context, server),
                                    onEdit: () =>
                                        _openForm(context, profile: server),
                                    onDelete: () => _delete(context, server),
                                  ),
                                );
                              }),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 13,
                                    color: colors.textTertiary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '凭据仅加密保存在本机，不会上传到任何第三方服务。',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colors.textTertiary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const Spacer(),
                            const SizedBox(height: 22),
                            Center(
                              child: Text(
                                'MTX 控制台 · 非官方 MediaMTX 客户端',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colors.textTertiary,
                                  fontSize: 9.5,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ExitChoice { background, stop }

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.profile,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ServerProfile profile;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(15, 15, 10, 15),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (profile.isLocal ? colors.success : scheme.primary)
                      .withValues(alpha: 0.2),
                  (profile.isLocal ? colors.success : scheme.primary)
                      .withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              profile.isLocal ? Icons.smartphone_rounded : Icons.dns_rounded,
              size: 22,
              color: profile.isLocal ? colors.success : scheme.primary,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
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
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (profile.isLocal) ...[
                      const SizedBox(width: 7),
                      StatusPill(
                        label: '本机',
                        color: colors.success,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  profile.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                ),
                if (profile.lastConnectedAt != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    '上次打开 ${relativeTime(profile.lastConnectedAt)}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: Icon(
              Icons.more_vert_rounded,
              color: colors.textTertiary,
              size: 20,
            ),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('编辑'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('删除'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocalRuntimeCard extends StatelessWidget {
  const _LocalRuntimeCard({required this.local});

  final LocalServerController local;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final running = local.phase == LocalPhase.running;
    return SurfaceCard(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LocalServerScreen())),
      padding: const EdgeInsets.all(15),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.success.withValues(alpha: 0.1), colors.surface],
      ),
      borderColor: colors.success.withValues(alpha: 0.3),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.success.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.smartphone_rounded,
              color: colors.success,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  running ? '本机 MediaMTX 正在运行' : '本机 MediaMTX 已安装',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${local.installedVersion} · ${running ? '127.0.0.1:${local.ports.api}' : local.phase.label}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.primary, size: 22),
        ],
      ),
    );
  }
}

class _GettingStarted extends StatelessWidget {
  const _GettingStarted({required this.onAdd, required this.onLocal});

  final VoidCallback onAdd;
  final VoidCallback onLocal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '三步开始',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _Step(
                index: '01',
                title: '启用 Control API',
                text: '在 mediamtx.yml 中设置 api: yes 和 apiAddress: :9997。',
              ),
              const _Step(
                index: '02',
                title: '授权手机访问',
                text: '放行防火墙 9997 端口；若设置了认证，请准备好账号。',
              ),
              const _Step(
                index: '03',
                title: '连接并开始管理',
                text: '添加服务器后即可查看实时路径、会话与配置。',
                last: true,
              ),
              const SizedBox(height: 6),
              const CodeBlock(code: 'api: yes\napiAddress: :9997'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onAdd,
                      child: const Text('添加服务器'),
                    ),
                  ),
                  const SizedBox(width: 9),
                  OutlinedButton(onPressed: onLocal, child: const Text('本机运行')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '提示：MediaMTX 的 API 默认关闭。若使用 Docker，请同时映射 9997/TCP 端口。',
          style: textTheme.bodySmall?.copyWith(
            color: colors.textTertiary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.title,
    required this.text,
    this.last = false,
  });

  final String index;
  final String title;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  index,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                    fontSize: 9,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: colors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 14 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
