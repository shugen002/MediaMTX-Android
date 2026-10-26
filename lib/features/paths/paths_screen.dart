import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/media_snapshot.dart';
import '../../state/app_state.dart';
import 'path_detail_screen.dart';
import 'path_editor_screen.dart';

enum PathFilter { all, online, offline, configured }

class PathsScreen extends StatefulWidget {
  const PathsScreen({super.key});

  @override
  State<PathsScreen> createState() => _PathsScreenState();
}

class _PathsScreenState extends State<PathsScreen> {
  final _search = TextEditingController();
  PathFilter _filter = PathFilter.all;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addPath() async {
    final app = context.read<AppState>();
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PathEditorScreen()));
    if (created == true) await app.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final snapshot = app.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final all = snapshot.pathViews;
    final filtered = all
        .where((path) {
          final matchesFilter = switch (_filter) {
            PathFilter.all => true,
            PathFilter.online => path.online,
            PathFilter.offline => !path.online,
            PathFilter.configured => path.hasConfig,
          };
          final query = _query.trim().toLowerCase();
          final matchesQuery =
              query.isEmpty ||
              path.name.toLowerCase().contains(query) ||
              path.sourceLabel.toLowerCase().contains(query);
          return matchesFilter && matchesQuery;
        })
        .toList(growable: false);

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
              Row(
                children: [
                  const TechLabel('PATHS'),
                  const Spacer(),
                  IconAction(
                    icon: Icons.add_rounded,
                    tooltip: '添加路径',
                    onPressed: _addPath,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '流媒体路径',
                      style: textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  Text(
                    '${all.length} 条',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '搜索路径名称或来源',
                  prefixIcon: const Icon(Icons.search_rounded, size: 21),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              ChoiceChipBar<PathFilter>(
                values: PathFilter.values,
                selected: _filter,
                labelBuilder: (value) => switch (value) {
                  PathFilter.all => '全部',
                  PathFilter.online => '在线',
                  PathFilter.offline => '离线',
                  PathFilter.configured => '已配置',
                },
                onSelected: (value) => setState(() => _filter = value),
              ),
              const SizedBox(height: 16),
              if (app.status == ServerConnectionStatus.offline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ErrorBanner(
                    message: app.error ?? '连接中断，显示上次同步的数据',
                    onRetry: () => app.refresh(),
                    compact: true,
                  ),
                ),
              if (filtered.isEmpty)
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    icon: Icons.route_rounded,
                    title: _query.isEmpty && _filter == PathFilter.all
                        ? '还没有路径'
                        : '没有匹配的路径',
                    message: _query.isEmpty && _filter == PathFilter.all
                        ? '通过 RTSP / RTMP / SRT 推流，或创建一条按需拉流配置。'
                        : '尝试修改搜索词或筛选条件。',
                    action: _query.isEmpty && _filter == PathFilter.all
                        ? FilledButton.icon(
                            onPressed: _addPath,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('创建路径'),
                          )
                        : null,
                  ),
                )
              else
                ...filtered.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PathCard(
                      view: path,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PathDetailScreen(pathName: path.name),
                          ),
                        );
                        if (context.mounted) await app.refresh();
                      },
                    ),
                  ),
                ),
              if (filtered.isNotEmpty) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '在线 ${all.where((path) => path.online).length} · '
                    '配置 ${all.where((path) => path.hasConfig).length} · '
                    '观看者 ${snapshot.totalReaders}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({required this.view, required this.onTap});

  final PathView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final runtime = view.runtime;
    final accent = view.online ? colors.success : colors.textTertiary;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  view.online ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: accent,
                  size: 21,
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
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${view.sourceLabel} · ${view.readers} 观看者',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: view.online ? '在线' : '离线',
                color: accent,
                pulse: view.online,
                dense: true,
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textTertiary,
                size: 20,
              ),
            ],
          ),
          if (runtime != null &&
              (runtime.tracks.isNotEmpty || view.hasConfig)) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final track in runtime.tracks.take(4))
                        _TrackTag(label: track.label),
                      if (view.hasConfig)
                        _TrackTag(
                          label: view.config!.alwaysAvailable ? '常驻' : '已配置',
                          color: colors.warning,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatBytes(view.outboundBytes),
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                    fontFamily: 'monospace',
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.upload_rounded,
                  size: 10,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackTag extends StatelessWidget {
  const _TrackTag({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: (color ?? colors.textSecondary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: (color ?? colors.border).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color ?? colors.textSecondary,
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
