import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/protocol_ui.dart';
import '../../core/utils/url_utils.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/traffic_chart.dart';
import '../../data/models/media_snapshot.dart';
import '../../data/models/server_info.dart';
import '../../data/models/server_profile.dart';
import '../../data/models/session_info.dart';
import '../../state/app_state.dart';
import '../paths/path_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final snapshot = app.snapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final pathViews = snapshot.pathViews;
    final onlinePaths = [
      ...pathViews.where((path) => path.online),
      ...pathViews.where((path) => !path.online),
    ];

    return RefreshIndicator(
      onRefresh: () => app.refresh(withSessions: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 112),
        child: ContentWidth(
          maxWidth: 1600,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const TechLabel('OVERVIEW'),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceHigh,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusDot(
                          color: colors.success,
                          size: 4,
                          pulse: app.refreshSeconds > 0,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          app.refreshSeconds > 0
                              ? '自动刷新 ${app.refreshSeconds}s'
                              : '手动刷新',
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textTertiary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '运行概览',
                      style: textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  Text(
                    formatShortDate(snapshot.fetchedAt),
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (app.status == ServerConnectionStatus.offline &&
                  app.error != null) ...[
                ErrorBanner(
                  message: '连接已中断 · 当前显示上次同步数据\n${app.error!}',
                  onRetry: () => app.refresh(),
                  compact: true,
                ),
                const SizedBox(height: 12),
              ],
              _ServerHero(
                info: snapshot.info,
                profile: app.active!,
                online: app.status == ServerConnectionStatus.online,
              ),
              const SizedBox(height: 13),
              _MetricGrid(
                snapshot: snapshot,
                inboundRate: app.inboundRate,
                outboundRate: app.outboundRate,
                onNavigate: onNavigate,
              ),
              const SizedBox(height: 14),
              _TrafficCard(app: app),
              SectionHeader(
                title: '协议会话',
                subtitle: '共 ${app.sessions.counts.total} 个活跃连接',
                action: TextButton(
                  onPressed: () => onNavigate(2),
                  child: const Text('查看全部'),
                ),
              ),
              _ProtocolGrid(
                onNavigate: onNavigate,
                counts: app.sessions.counts,
              ),
              SectionHeader(
                title: '路径状态',
                subtitle:
                    '${snapshot.onlinePaths}/${snapshot.paths.length} 条在线',
                action: TextButton(
                  onPressed: () => onNavigate(1),
                  child: const Text('全部路径'),
                ),
              ),
              if (pathViews.isEmpty)
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    icon: Icons.route_rounded,
                    title: '还没有路径',
                    message: '推流或添加路径配置后，会在这里看到实时状态。',
                    compact: true,
                    action: TextButton(
                      onPressed: () => onNavigate(1),
                      child: const Text('去添加路径'),
                    ),
                  ),
                )
              else
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (
                        var i = 0;
                        i < math.min(4, onlinePaths.length);
                        i++
                      ) ...[
                        _MiniPathRow(
                          view: onlinePaths[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PathDetailScreen(
                                pathName: onlinePaths[i].name,
                              ),
                            ),
                          ),
                        ),
                        if (i < math.min(4, onlinePaths.length) - 1)
                          Divider(color: colors.border, height: 1),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'MediaMTX ${snapshot.info.version} · 数据来自 Control API',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerHero extends StatelessWidget {
  const _ServerHero({
    required this.info,
    required this.profile,
    required this.online,
  });

  final ServerInfo info;
  final ServerProfile profile;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final gradient = colors.isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF122845), Color(0xFF0C1726)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1748C8), Color(0xFF102E82)],
          );
    final apiUri = Uri.tryParse(normalizeBaseUrl(profile.baseUrl));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -36,
            child: CustomPaint(
              size: const Size(210, 210),
              painter: _SignalPainter(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            right: 22,
            bottom: 24,
            child: Icon(
              Icons.podcasts_rounded,
              size: 74,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusPill(
                      label: online ? 'API ONLINE' : 'DISCONNECTED',
                      color: online
                          ? const Color(0xFF43E6B4)
                          : const Color(0xFFFF7A8A),
                      pulse: online,
                      dense: true,
                    ),
                    const Spacer(),
                    Text(
                      'CONTROL API',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.42),
                        letterSpacing: 1.5,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'MediaMTX',
                  style: textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.version,
                  style: textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '运行时长',
                            style: textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 9.5,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 5),
                          _LiveUptime(started: info.started),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'API 地址',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 9.5,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          apiUri == null
                              ? profile.baseUrl
                              : '${apiUri.host}:${apiUri.hasPort ? apiUri.port : (apiUri.scheme == 'https' ? 443 : 80)}',
                          style: textTheme.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  _SignalPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final center = Offset(size.width * 0.62, size.height * 0.55);
    for (var i = 1; i <= 4; i++) {
      final radius = 26.0 * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi * 0.9,
        math.pi * 0.8,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _LiveUptime extends StatefulWidget {
  const _LiveUptime({required this.started});

  final DateTime started;

  @override
  State<_LiveUptime> createState() => _LiveUptimeState();
}

class _LiveUptimeState extends State<_LiveUptime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uptime = DateTime.now().difference(widget.started);
    return Text(
      formatUptime(uptime),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 19,
        letterSpacing: -0.4,
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.snapshot,
    required this.inboundRate,
    required this.outboundRate,
    required this.onNavigate,
  });

  final MediaSnapshot snapshot;
  final double inboundRate;
  final double outboundRate;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        final tiles = [
          MetricTile(
            label: '在线路径',
            value: '${snapshot.onlinePaths}',
            unit: '/ ${snapshot.paths.length}',
            icon: Icons.route_rounded,
            accent: colors.info,
            footnote: 'PATHS',
            onTap: () => onNavigate(1),
          ),
          MetricTile(
            label: '观看连接',
            value: '${snapshot.totalReaders}',
            unit: '个',
            icon: Icons.visibility_outlined,
            accent: colors.success,
            footnote: 'VIEWS',
            onTap: () => onNavigate(2),
          ),
          MetricTile(
            label: '入站累计',
            value: formatBytes(snapshot.inboundBytes),
            icon: Icons.south_west_rounded,
            accent: colors.chartIn,
            footnote: formatRate(inboundRate),
            onTap: () => onNavigate(2),
          ),
          MetricTile(
            label: '出站累计',
            value: formatBytes(snapshot.outboundBytes),
            icon: Icons.north_east_rounded,
            accent: colors.chartOut,
            footnote: formatRate(outboundRate),
            onTap: () => onNavigate(2),
          ),
        ];
        Widget row(List<Widget> items) => SizedBox(
          height: wide ? 134 : 132,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: items[i]),
              ],
            ],
          ),
        );
        if (wide) return row(tiles);
        return Column(
          children: [
            row(tiles.sublist(0, 2)),
            const SizedBox(height: 10),
            row(tiles.sublist(2, 4)),
          ],
        );
      },
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '实时流量',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _Legend(color: colors.chartIn, label: '入站'),
              const SizedBox(width: 12),
              _Legend(color: colors.chartOut, label: '出站'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _RateValue(
                label: 'IN',
                value: formatRate(app.inboundRate),
                color: colors.chartIn,
                icon: Icons.south_west_rounded,
              ),
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: 18),
                color: colors.border,
              ),
              _RateValue(
                label: 'OUT',
                value: formatRate(app.outboundRate),
                color: colors.chartOut,
                icon: Icons.north_east_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TrafficChart(samples: app.traffic),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.colors.textTertiary,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _RateValue extends StatelessWidget {
  const _RateValue({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: context.colors.textTertiary,
                  fontSize: 8.5,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: textTheme.titleSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProtocolGrid extends StatelessWidget {
  const _ProtocolGrid({required this.onNavigate, required this.counts});

  final ValueChanged<int> onNavigate;
  final SessionCounts counts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 6 : 3;
        final itemWidth = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final protocol in SessionProtocol.values)
              SizedBox(
                width: itemWidth,
                child: InkWell(
                  onTap: () => onNavigate(2),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              protocolIcon(protocol),
                              size: 16,
                              color: protocolColor(protocol, colors),
                            ),
                            const Spacer(),
                            Text(
                              '${counts.of(protocol)}',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          protocol.label,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiniPathRow extends StatelessWidget {
  const _MiniPathRow({required this.view, required this.onTap});

  final PathView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final runtime = view.runtime;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (view.online ? colors.success : colors.textTertiary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 18,
                color: view.online ? colors.success : colors.textTertiary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    view.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${view.sourceLabel} · ${view.readers} 位观看者',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (runtime != null && runtime.tracks.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (final track in runtime.tracks.take(2))
                      _TrackTag(label: track.label),
                  ],
                ),
              ),
            const SizedBox(width: 4),
            StatusDot(
              color: view.online ? colors.success : colors.textTertiary,
              size: 5,
              pulse: view.online,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackTag extends StatelessWidget {
  const _TrackTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 8,
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
