import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/url_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/path_config.dart';
import '../../data/local/local_server_controller.dart';
import '../../data/models/runtime_path.dart';
import '../../state/app_state.dart';
import 'path_editor_screen.dart';

class PathDetailScreen extends StatefulWidget {
  const PathDetailScreen({super.key, required this.pathName});

  final String pathName;

  @override
  State<PathDetailScreen> createState() => _PathDetailScreenState();
}

class _PathDetailScreenState extends State<PathDetailScreen> {
  RuntimePath? _runtime;
  PathConfig? _config;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final snapshot = context.read<AppState>().snapshot;
    if (snapshot != null) {
      for (final view in snapshot.pathViews) {
        if (view.name == widget.pathName) {
          _runtime = view.runtime;
          _config = view.config;
          break;
        }
      }
    }
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final service = app.service;
    if (service == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      RuntimePath? runtime;
      PathConfig? config;
      try {
        runtime = await service.path(widget.pathName);
      } on ApiException catch (error) {
        if (error.kind != ApiErrorKind.notFound) rethrow;
      }
      try {
        final raw = await service.pathConfig(widget.pathName);
        config = PathConfig(
          name: widget.pathName,
          raw: Map<String, dynamic>.from(raw)..remove('name'),
        );
      } on ApiException catch (error) {
        if (error.kind != ApiErrorKind.notFound) rethrow;
      }
      if (!mounted) return;
      setState(() {
        _runtime = runtime;
        _config = config;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.friendlyMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await _load();
    if (mounted) await context.read<AppState>().refresh(silent: true);
  }

  Future<void> _editConfig() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            PathEditorScreen(pathName: widget.pathName, config: _config),
      ),
    );
    if (saved == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _deleteConfig() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除路径配置？',
      message: '将删除「${widget.pathName}」的持久化配置。正在进行的推流和动态路径不会立即断开。',
      confirmLabel: '删除配置',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final app = context.read<AppState>();
    try {
      await app.requireService.deletePath(widget.pathName);
      if (!mounted) return;
      showAppSnack(context, '路径配置已删除');
      await app.refresh();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) showAppSnack(context, error.friendlyMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final local = context.watch<LocalServerController>();
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final runtime = _runtime;
    final config = _config;
    final online = runtime?.online ?? false;
    final source =
        runtime?.source?.label ??
        (config?.source.isNotEmpty == true ? config!.source : '未发布');
    final endpoints = buildStreamEndpoints(
      app.active!,
      widget.pathName,
      app.globalConfig,
      hostOverride: app.active!.isLocal ? local.lanAddress : null,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('路径详情'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editConfig();
              if (value == 'delete') _deleteConfig();
              if (value == 'copy') copyText(context, widget.pathName);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('复制路径名'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('编辑配置'),
                  ],
                ),
              ),
              if (config != null)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('删除配置'),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AppBackdrop(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
            child: ContentWidth(
              maxWidth: 1600,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    ErrorBanner(
                      message: _error!,
                      onRetry: _load,
                      onClose: () => setState(() => _error = null),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(19, 18, 19, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: online
                            ? [const Color(0xFF123B31), const Color(0xFF0B1B18)]
                            : [colors.surfaceHigh, colors.surface],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: online
                            ? colors.success.withValues(alpha: 0.3)
                            : colors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StatusPill(
                              label: online ? 'ONLINE' : 'OFFLINE',
                              color: online
                                  ? colors.success
                                  : colors.textTertiary,
                              pulse: online,
                              dense: true,
                            ),
                            const Spacer(),
                            TechLabel(
                              'PATH',
                              color: online
                                  ? colors.success.withValues(alpha: 0.7)
                                  : colors.textTertiary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.pathName,
                          style: textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: online ? Colors.white : null,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          source,
                          style: textTheme.bodySmall?.copyWith(
                            color: online
                                ? Colors.white.withValues(alpha: 0.65)
                                : colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _HeroStat(
                              label: '观看者',
                              value: '${runtime?.readers.length ?? 0}',
                              online: online,
                            ),
                            const SizedBox(width: 28),
                            _HeroStat(
                              label: '在线时长',
                              value: runtime?.onlineTime == null
                                  ? '—'
                                  : durationBetween(runtime!.onlineTime),
                              online: online,
                            ),
                            const SizedBox(width: 28),
                            _HeroStat(
                              label: '轨道',
                              value: '${runtime?.tracks.length ?? 0}',
                              online: online,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniMetric(
                          label: '入站',
                          value: formatBytes(runtime?.inboundBytes ?? 0),
                          icon: Icons.south_west_rounded,
                          color: colors.chartIn,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _MiniMetric(
                          label: '出站',
                          value: formatBytes(runtime?.outboundBytes ?? 0),
                          icon: Icons.north_east_rounded,
                          color: colors.chartOut,
                        ),
                      ),
                    ],
                  ),
                  SectionHeader(
                    title: '轨道',
                    subtitle: '编码器与媒体参数',
                    padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
                  ),
                  SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: runtime == null || runtime.tracks.isEmpty
                        ? Text(
                            '当前没有活动轨道。推流开始后会显示视频、音频编码信息。',
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          )
                        : Column(
                            children: [
                              for (
                                var i = 0;
                                i < runtime.tracks.length;
                                i++
                              ) ...[
                                _TrackRow(track: runtime.tracks[i]),
                                if (i < runtime.tracks.length - 1)
                                  Divider(color: colors.border, height: 17),
                              ],
                            ],
                          ),
                  ),
                  SectionHeader(
                    title: '观看会话',
                    subtitle: '${runtime?.readers.length ?? 0} 个读取端',
                    padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
                  ),
                  SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: runtime == null || runtime.readers.isEmpty
                        ? Text(
                            '暂无观看会话',
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          )
                        : Column(
                            children: [
                              for (
                                var i = 0;
                                i < runtime.readers.length;
                                i++
                              ) ...[
                                Row(
                                  children: [
                                    Icon(
                                      Icons.play_circle_outline_rounded,
                                      size: 17,
                                      color: colors.textTertiary,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        runtime.readers[i].label,
                                        style: textTheme.bodySmall,
                                      ),
                                    ),
                                    Text(
                                      runtime.readers[i].id.length > 8
                                          ? runtime.readers[i].id.substring(
                                              0,
                                              8,
                                            )
                                          : runtime.readers[i].id,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colors.textTertiary,
                                        fontFamily: 'monospace',
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                                if (i < runtime.readers.length - 1)
                                  Divider(color: colors.border, height: 17),
                              ],
                            ],
                          ),
                  ),
                  SectionHeader(
                    title: '路径配置',
                    subtitle: '持久化在 MediaMTX 服务端',
                    action: TextButton(
                      onPressed: _editConfig,
                      child: Text(config == null ? '创建配置' : '编辑'),
                    ),
                    padding: const EdgeInsets.fromLTRB(2, 22, 2, 8),
                  ),
                  SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(15, 8, 15, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (config == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              '这是一条运行时动态路径，没有持久化配置。重启服务后需要重新推流或创建配置。',
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                                height: 1.55,
                              ),
                            ),
                          )
                        else ...[
                          InfoRow(
                            label: '名称',
                            value: widget.pathName,
                            copyable: true,
                          ),
                          InfoRow(
                            label: '来源',
                            value: config.source.isEmpty
                                ? '等待推流'
                                : config.source,
                            copyable: config.source.isNotEmpty,
                            monospace: true,
                          ),
                          InfoRow(
                            label: '常驻可用',
                            value: config.alwaysAvailable ? '是' : '否',
                          ),
                          InfoRow(
                            label: '按需拉流',
                            value: config.sourceOnDemand ? '是' : '否',
                          ),
                          InfoRow(
                            label: '录制',
                            value: config.record
                                ? (config.recordPath.isEmpty
                                      ? '开启'
                                      : config.recordPath)
                                : '关闭',
                          ),
                          InfoRow(
                            label: '最大观看',
                            value: config.maxReaders == 0
                                ? '不限制'
                                : '${config.maxReaders}',
                          ),
                          if (config.runOnDemand != null)
                            InfoRow(
                              label: '按需命令',
                              value: config.runOnDemand!,
                              monospace: true,
                            ),
                          const SizedBox(height: 6),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(top: 4),
                            title: Text(
                              '原始 JSON 配置',
                              style: textTheme.labelMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            iconColor: colors.textTertiary,
                            collapsedIconColor: colors.textTertiary,
                            children: [
                              CodeBlock(
                                code: const JsonEncoder.withIndent('  ')
                                    .convert(config.raw),
                                maxHeight: 240,
                                onCopy: () => copyText(
                                  context,
                                  const JsonEncoder.withIndent('  ')
                                      .convert(config.raw),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  SectionHeader(
                    title: '推流 & 播放地址',
                    subtitle: '根据当前服务器地址和全局端口生成',
                    padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
                  ),
                  SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(15, 8, 15, 12),
                    child: Column(
                      children: [
                        for (final endpoint in endpoints)
                          _EndpointRow(endpoint: endpoint),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _editConfig,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(config == null ? '创建配置' : '编辑配置'),
                        ),
                      ),
                      if (config != null) ...[
                        const SizedBox(width: 9),
                        OutlinedButton(
                          onPressed: _deleteConfig,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.danger,
                            side: BorderSide(
                              color: colors.danger.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Text('删除'),
                        ),
                      ],
                    ],
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

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.online,
  });

  final String label;
  final String value;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: online
                ? Colors.white.withValues(alpha: 0.45)
                : colors.textTertiary,
            fontSize: 9,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: online ? Colors.white : null,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.textTertiary, fontSize: 9),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track});

  final PathTrackInfo track;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final props = track.codecProps;
    String? details;
    if (props['width'] != null && props['height'] != null) {
      details = '${props['width']}×${props['height']}';
      if (props['profile'] != null) details = '$details · ${props['profile']}';
    } else if (props['sampleRate'] != null) {
      details = '${props['sampleRate']} Hz';
      if (props['channelCount'] != null) {
        details = '$details · ${props['channelCount']} ch';
      }
    }
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (track.isVideo ? colors.chartIn : colors.chartOut)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            track.isVideo
                ? Icons.videocam_outlined
                : track.isAudio
                ? Icons.graphic_eq_rounded
                : Icons.data_object_rounded,
            size: 18,
            color: track.isVideo ? colors.chartIn : colors.chartOut,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.label,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (details != null)
                Text(
                  details,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
        TechLabel(
          track.isVideo
              ? 'VIDEO'
              : track.isAudio
              ? 'AUDIO'
              : 'DATA',
          fontSize: 8,
        ),
      ],
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.endpoint});

  final StreamEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  endpoint.label,
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                endpoint.publishUrl.isEmpty ? '播放' : '播放 / 推流',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  fontSize: 8.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _UrlLine(
            label: endpoint.publishUrl.isEmpty ? '播放' : '播放',
            url: endpoint.readUrl,
          ),
          if (endpoint.publishUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            _UrlLine(label: '推流', url: endpoint.publishUrl),
          ],
        ],
      ),
    );
  }
}

class _UrlLine extends StatelessWidget {
  const _UrlLine({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => copyText(context, url),
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  fontSize: 8.5,
                ),
              ),
            ),
            Expanded(
              child: Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.copy_rounded, size: 12, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}
