import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_exception.dart';
import '../../data/api/mediamtx_service.dart';
import '../../state/app_state.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<Recording> _recordings = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      final recordings = await service.recordings();
      if (mounted) setState(() => _recordings = recordings);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.friendlyMessage);
    } catch (error) {
      if (mounted) setState(() => _error = '加载录制失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteSegment(
    Recording recording,
    RecordingSegment segment,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除录制片段？',
      message:
          '${recording.name}\n${formatDateTime(segment.start)} 开始的片段将从磁盘删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final app = context.read<AppState>();
    try {
      await app.requireService.deleteRecordingSegment(
        path: recording.name,
        start: segment.start,
      );
      if (!mounted) return;
      showAppSnack(context, '片段已删除');
      await _load();
    } on ApiException catch (error) {
      if (mounted) showAppSnack(context, error.friendlyMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final totalSegments = _recordings.fold<int>(
      0,
      (sum, item) => sum + item.segments.length,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('录制文件'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AppBackdrop(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
            child: ContentWidth(
              maxWidth: 1600,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '服务端 recordings 目录下的文件。删除操作不可恢复。',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (_recordings.isNotEmpty)
                        TechLabel('$totalSegments SEGMENTS'),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    ErrorBanner(message: _error!, onRetry: _load),
                  ],
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 70),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    )
                  else if (_recordings.isEmpty)
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: EmptyState(
                        icon: Icons.video_library_outlined,
                        title: '暂无录制文件',
                        message: '在路径配置中开启「录制」，流开始后会自动生成分段文件。',
                        action: FilledButton(
                          onPressed: _load,
                          child: const Text('重新加载'),
                        ),
                      ),
                    )
                  else
                    ..._recordings.map(
                      (recording) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RecordingCard(
                          recording: recording,
                          onDelete: (segment) =>
                              _deleteSegment(recording, segment),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '提示：播放录制需要额外启用 MediaMTX playback 服务。',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
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

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.recording, required this.onDelete});

  final Recording recording;
  final ValueChanged<RecordingSegment> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final latest = recording.latest;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(15, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
          iconColor: colors.textTertiary,
          collapsedIconColor: colors.textTertiary,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.movie_outlined, size: 19, color: colors.danger),
          ),
          title: Text(
            recording.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${recording.segments.length} 个片段'
            '${latest == null ? '' : ' · 最近 ${relativeTime(latest)}'}',
            style: textTheme.labelSmall?.copyWith(
              color: colors.textTertiary,
              fontSize: 10,
            ),
          ),
          children: [
            Divider(color: colors.border, height: 1),
            if (recording.segments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  '没有分段信息',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              ...recording.segments.reversed
                  .take(30)
                  .map(
                    (segment) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 5,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              formatDateTime(segment.start),
                              style: textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                          Text(
                            segment.duration == null
                                ? '—'
                                : formatDurationShort(segment.duration!),
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                              fontSize: 9.5,
                            ),
                          ),
                          const SizedBox(width: 3),
                          IconButton(
                            onPressed: () => onDelete(segment),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: colors.danger.withValues(alpha: 0.7),
                            ),
                            tooltip: '删除片段',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
            if (recording.segments.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '仅显示最近 30 个片段',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
