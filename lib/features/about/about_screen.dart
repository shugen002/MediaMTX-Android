import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: AppBackdrop(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
          child: ContentWidth(
            maxWidth: 1000,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const SizedBox(height: 16),
                const BrandMark(size: 76),
                const SizedBox(height: 18),
                Text(
                  'MTX 控制台',
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 5),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) => Text(
                    'v${snapshot.data?.version ?? '1.0.1'} · Flutter',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '为 MediaMTX 打造的移动控制台。\n连接、观察并管理你的流媒体服务。',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 26),
                SurfaceCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '能力',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _Feature(
                        icon: Icons.speed_rounded,
                        title: '实时概览',
                        text: '服务器状态、路径、观看者与流量走势',
                      ),
                      const _Feature(
                        icon: Icons.route_rounded,
                        title: '路径与推流',
                        text: '管理来源、录制、按需拉流，复制推流地址',
                      ),
                      const _Feature(
                        icon: Icons.bolt_rounded,
                        title: '会话控制',
                        text: 'RTSP / RTMP / SRT / WebRTC / HLS / MoQ',
                      ),
                      const _Feature(
                        icon: Icons.smartphone_rounded,
                        title: '本机运行',
                        text: '在手机上直接运行最新版 MediaMTX',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _LinkRow(
                        icon: Icons.code_rounded,
                        label: 'MediaMTX on GitHub',
                        onTap: () => launchUrl(
                          Uri.parse('https://github.com/bluenviron/mediamtx'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      Divider(color: colors.border, height: 1),
                      _LinkRow(
                        icon: Icons.menu_book_outlined,
                        label: 'Control API 文档',
                        onTap: () => launchUrl(
                          Uri.parse('https://mediamtx.org/docs/'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      Divider(color: colors.border, height: 1),
                      _LinkRow(
                        icon: Icons.balance_rounded,
                        label: '开源许可',
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'MTX 控制台',
                          applicationVersion: 'v1.0.1',
                          applicationIcon: const Padding(
                            padding: EdgeInsets.all(12),
                            child: BrandMark(size: 52),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 17,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '无遥测、无广告。服务器凭据仅加密保存在本机；本机服务端二进制从 GitHub 官方 Release 下载并校验 SHA-256。',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 10.5,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'MediaMTX 是 bluenviron 的开源项目，本项目与之无官方关联。',
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                    fontSize: 9.5,
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

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: colors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: colors.textSecondary),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 15,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
