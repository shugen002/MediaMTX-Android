import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/url_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/local/local_server_controller.dart';
import '../../state/app_state.dart';
import '../about/about_screen.dart';
import '../local/local_server_screen.dart';
import '../recordings/recordings_screen.dart';
import '../servers/server_form_screen.dart';
import '../settings/settings_screen.dart';
import '../users/users_screen.dart';
import 'config_viewer_screen.dart';

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final local = context.watch<LocalServerController>();
    final snapshot = app.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final profile = app.active!;

    return RefreshIndicator(
      onRefresh: () => app.refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 112),
        child: ContentWidth(
          maxWidth: 1600,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TechLabel('MANAGE'),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '管理',
                      style: textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  Text(
                    snapshot.info.version,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.surfaceHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.border),
                          ),
                          child: Icon(
                            Icons.dns_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                hostWithPort(profile),
                                style: textTheme.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StatusPill(
                          label: app.isConnected ? '已连接' : '离线',
                          color: app.isConnected
                              ? colors.success
                              : colors.danger,
                          pulse: app.isConnected,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Divider(color: colors.border, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ServerMeta(
                            label: '运行时长',
                            value: snapshot.info.uptimeLabel,
                          ),
                        ),
                        Expanded(
                          child: _ServerMeta(
                            label: '路径',
                            value:
                                '${snapshot.onlinePaths}/${snapshot.paths.length} 在线',
                          ),
                        ),
                        Expanded(
                          child: _ServerMeta(
                            label: '观看者',
                            value: '${snapshot.totalReaders}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ServerFormScreen(profile: profile),
                          ),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 17),
                        label: const Text('连接与认证设置'),
                      ),
                    ),
                  ],
                ),
              ),
              SectionHeader(
                title: '服务端工具',
                subtitle: '配置、用户和录制文件',
                padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 760 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: columns == 4 ? 1.45 : 1.75,
                    children: [
                      _ToolTile(
                        icon: Icons.tune_rounded,
                        title: '全局配置',
                        subtitle: '读写服务端配置',
                        color: colors.chartIn,
                        onTap: () => _openConfig(context, ConfigKind.global),
                      ),
                      _ToolTile(
                        icon: Icons.account_tree_outlined,
                        title: '路径默认值',
                        subtitle: '新路径的默认参数',
                        color: colors.warning,
                        onTap: () =>
                            _openConfig(context, ConfigKind.pathDefaults),
                      ),
                      _ToolTile(
                        icon: Icons.group_outlined,
                        title: '访问控制',
                        subtitle: '内部用户与权限',
                        color: colors.success,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const UsersScreen(),
                          ),
                        ),
                      ),
                      _ToolTile(
                        icon: Icons.video_library_outlined,
                        title: '录制文件',
                        subtitle: '浏览与清理录制',
                        color: const Color(0xFFB48CFF),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RecordingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              SectionHeader(
                title: '本机与外观',
                subtitle: '手机端运行时和显示偏好',
                padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
              ),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ListAction(
                      icon: Icons.smartphone_rounded,
                      title: '本机 MediaMTX',
                      subtitle: local.install == null
                          ? '下载最新版并在手机上运行'
                          : '${local.installedVersion} · ${local.phase.label}',
                      trailing: StatusPill(
                        label: local.isRunning ? '运行中' : '未运行',
                        color: local.isRunning
                            ? colors.success
                            : colors.textTertiary,
                        dense: true,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LocalServerScreen(),
                        ),
                      ),
                    ),
                    Divider(color: colors.border, height: 1),
                    _ListAction(
                      icon: Icons.palette_outlined,
                      title: '外观与偏好',
                      subtitle: _themeLabel(app.themeMode),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                    Divider(color: colors.border, height: 1),
                    _ListAction(
                      icon: Icons.info_outline_rounded,
                      title: '关于 MTX 控制台',
                      subtitle: '版本、开源许可与技术说明',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: '断开连接？',
                      message: '将返回服务器列表，不会停止服务端。',
                      confirmLabel: '断开',
                    );
                    if (confirmed) await app.disconnect();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                    side: BorderSide(
                      color: colors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('断开当前服务器'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openConfig(BuildContext context, ConfigKind kind) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ConfigViewerScreen(kind: kind)));
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色模式',
    ThemeMode.dark => '深色模式',
  };
}

class _ServerMeta extends StatelessWidget {
  const _ServerMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      radius: 17,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_outward_rounded,
                size: 14,
                color: colors.textTertiary,
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.textTertiary, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _ListAction extends StatelessWidget {
  const _ListAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.textTertiary, fontSize: 10),
                  ),
                ],
              ),
            ),
            ?trailing,
            const SizedBox(width: 5),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
