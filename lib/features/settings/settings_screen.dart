import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/local/local_server_controller.dart';
import '../../state/app_state.dart';
import '../about/about_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _mirror;
  bool _mirrorInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_mirrorInitialized) {
      _mirror = TextEditingController(
        text: context.read<LocalServerController>().mirrorPrefix,
      );
      _mirrorInitialized = true;
    }
  }

  @override
  void dispose() {
    if (_mirrorInitialized) _mirror.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final local = context.watch<LocalServerController>();
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('偏好设置')),
      body: AppBackdrop(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
          child: ContentWidth(
            maxWidth: 1200,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TechLabel('APPEARANCE'),
                const SizedBox(height: 9),
                Text(
                  '外观',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      for (final mode in ThemeMode.values)
                        Expanded(
                          child: _ThemeOption(
                            mode: mode,
                            selected: app.themeMode == mode,
                            onTap: () => app.setThemeMode(mode),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '深色模式针对 AMOLED 屏幕优化，切换会立即应用。',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 24),
                const TechLabel('REFRESH'),
                const SizedBox(height: 9),
                Text(
                  '数据刷新',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自动刷新间隔',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '页面可见时在后台同步服务器状态。间隔越短越实时，也越耗电。',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final seconds in [5, 10, 30, 60, 0])
                            ChoiceChip(
                              label: Text(seconds == 0 ? '关闭' : '$seconds 秒'),
                              selected: app.refreshSeconds == seconds,
                              selectedColor: scheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              checkmarkColor: scheme.primary,
                              side: BorderSide(
                                color: app.refreshSeconds == seconds
                                    ? scheme.primary.withValues(alpha: 0.45)
                                    : colors.border,
                              ),
                              labelStyle: textTheme.labelMedium?.copyWith(
                                color: app.refreshSeconds == seconds
                                    ? scheme.primary
                                    : colors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (_) => app.setRefreshSeconds(seconds),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const TechLabel('LOCAL RUNTIME'),
                const SizedBox(height: 9),
                Text(
                  '本机下载',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('使用 GitHub 加速镜像'),
                        subtitle: const Text('国内下载更稳定；安装包仍会校验官方 SHA-256'),
                        value: local.mirrorEnabled,
                        onChanged: (value) => local.setMirror(enabled: value),
                      ),
                      if (local.mirrorEnabled) ...[
                        const SizedBox(height: 4),
                        TextField(
                          controller: _mirror,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          style: textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                          decoration: InputDecoration(
                            labelText: '加速前缀',
                            hintText: 'https://ghfast.top/',
                            suffixIcon: IconButton(
                              onPressed: () async {
                                await local.setMirror(
                                  enabled: true,
                                  prefix: _mirror.text,
                                );
                                if (context.mounted) {
                                  showAppSnack(context, '加速地址已保存');
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 19),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '第三方镜像仅用于加速下载，不接触你的服务器凭据。',
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const TechLabel('ABOUT'),
                const SizedBox(height: 9),
                Text(
                  '其它',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingsRow(
                        icon: Icons.info_outline_rounded,
                        title: '关于 MTX 控制台',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AboutScreen(),
                          ),
                        ),
                      ),
                      Divider(color: colors.border, height: 1),
                      _SettingsRow(
                        icon: Icons.article_outlined,
                        title: 'MediaMTX 文档',
                        onTap: () => launchUrl(
                          Uri.parse('https://mediamtx.org/docs/'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      Divider(color: colors.border, height: 1),
                      _SettingsRow(
                        icon: Icons.code_rounded,
                        title: 'GitHub 项目',
                        onTap: () => launchUrl(
                          Uri.parse('https://github.com/bluenviron/mediamtx'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version ?? '1.0.2';
                      return Column(
                        children: [
                          Text(
                            'MTX 控制台 v$version',
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '非官方 MediaMTX 管理客户端',
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    scheme.brightness == Brightness.dark
                        ? 'UI · DARK'
                        : 'UI · LIGHT',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary.withValues(alpha: 0.5),
                      letterSpacing: 1,
                      fontSize: 8,
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

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto_rounded, '跟随系统'),
      ThemeMode.light => (Icons.light_mode_rounded, '浅色'),
      ThemeMode.dark => (Icons.dark_mode_rounded, '深色'),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 21,
              color: selected ? scheme.primary : colors.textTertiary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? scheme.primary : colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 19, color: colors.textSecondary),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
