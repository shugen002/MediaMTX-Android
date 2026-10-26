import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/protocol_ui.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/session_info.dart';
import '../../state/app_state.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  SessionProtocol _selected = SessionProtocol.rtsp;
  List<SessionInfo> _sessions = const [];
  bool _loading = true;
  String? _error;
  String? _serverId;
  Timer? _timer;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _timer = Timer.periodic(const Duration(seconds: 9), (_) {
        if (mounted) _load(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final app = context.read<AppState>();
    final service = app.service;
    if (service == null) return;
    final token = ++_loadToken;
    final protocol = _selected;
    if (!silent) setState(() => _loading = true);
    try {
      final sessions = await service.sessions(protocol);
      if (!mounted || token != _loadToken || protocol != _selected) return;
      setState(() {
        _sessions = sessions;
        _error = null;
      });
      if (app.sessions.counts.total == 0) {
        unawaited(app.refreshSessionCounts());
      }
    } on ApiException catch (error) {
      if (mounted && token == _loadToken) {
        setState(() => _error = error.friendlyMessage);
      }
    } catch (error) {
      if (mounted && token == _loadToken) {
        setState(() => _error = '加载会话失败：$error');
      }
    } finally {
      if (mounted && token == _loadToken) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _select(SessionProtocol protocol) async {
    if (_selected == protocol) return;
    setState(() {
      _selected = protocol;
      _sessions = const [];
      _loading = true;
      _error = null;
    });
    await _load();
  }

  Future<void> _kick(SessionInfo session) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '结束会话？',
      message:
          '将强制断开 ${session.protocolLabel} 会话「${session.path.isEmpty ? session.id : session.path}」。',
      confirmLabel: '断开',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final app = context.read<AppState>();
    try {
      await app.requireService.kick(session);
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnack(context, '会话已断开');
      await _load(silent: true);
      await app.refreshSessionCounts();
    } on ApiException catch (error) {
      if (mounted) showAppSnack(context, error.friendlyMessage, error: true);
    }
  }

  void _openDetail(SessionInfo session) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _SessionDetailSheet(session: session, onKick: () => _kick(session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_serverId != app.active?.id) {
      _serverId = app.active?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _sessions = const [];
            _loading = true;
          });
          _load();
          app.refreshSessionCounts();
        }
      });
    }
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final counts = app.sessions.counts;

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await app.refreshSessionCounts();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 112),
        child: ContentWidth(
          maxWidth: 1600,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TechLabel('SESSIONS'),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '活跃会话',
                      style: textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  Text(
                    '${counts.total} 个连接',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ChoiceChipBar<SessionProtocol>(
                values: SessionProtocol.values,
                selected: _selected,
                badgeBuilder: (protocol) => counts.of(protocol),
                labelBuilder: (protocol) => protocol.label,
                onSelected: _select,
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                ErrorBanner(
                  message: _error!,
                  onRetry: () => _load(),
                  onClose: () => setState(() => _error = null),
                  compact: true,
                ),
                const SizedBox(height: 10),
              ],
              if (_loading && _sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                )
              else if (_sessions.isEmpty)
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    icon: protocolIcon(_selected),
                    title: '暂无 ${_selected.label} 会话',
                    message:
                        '当客户端连接、推流或播放时，会话会实时出现在这里。\n${_selected.description}',
                    compact: true,
                  ),
                )
              else
                ..._sessions.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _SessionCard(
                      session: session,
                      onTap: () => _openDetail(session),
                    ),
                  ),
                ),
              if (_sessions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '每 9 秒自动刷新 · 下拉立即更新',
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

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap});

  final SessionInfo session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final accent = protocolColor(session.protocol, colors);
    final publishing = session.isPublishing;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  protocolIcon(session.protocol),
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.path.isEmpty ? '未命名路径' : session.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (session.secure) ...[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.lock_rounded,
                            size: 11,
                            color: colors.success,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.remoteAddr.isEmpty
                          ? session.protocolLabel
                          : session.remoteAddr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: session.stateLabel,
                color: publishing ? colors.warning : accent,
                pulse: publishing,
                dense: true,
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textTertiary,
                size: 19,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SessionMeta(
                icon: Icons.schedule_rounded,
                text: session.durationLabel,
              ),
              const SizedBox(width: 14),
              if (session.user.isNotEmpty) ...[
                _SessionMeta(
                  icon: Icons.person_outline_rounded,
                  text: session.user,
                ),
                const SizedBox(width: 14),
              ],
              if (session.transport.isNotEmpty)
                _SessionMeta(
                  icon: Icons.alt_route_rounded,
                  text: session.transport,
                ),
              const Spacer(),
              Text(
                formatBytes(session.totalBytes),
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionMeta extends StatelessWidget {
  const _SessionMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: colors.textTertiary),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.textTertiary, fontSize: 9.5),
        ),
      ],
    );
  }
}

class _SessionDetailSheet extends StatelessWidget {
  const _SessionDetailSheet({required this.session, required this.onKick});

  final SessionInfo session;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final accent = protocolColor(session.protocol, colors);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, controller) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(protocolIcon(session.protocol), color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.path.isEmpty ? '未命名会话' : session.path,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${session.protocolLabel} · ${session.stateLabel}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: session.stateLabel,
                    color: session.isPublishing ? colors.warning : accent,
                    pulse: session.isPublishing,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(15, 6, 15, 8),
                child: Column(
                  children: [
                    InfoRow(label: '会话 ID', value: session.id, copyable: true),
                    InfoRow(
                      label: '路径',
                      value: session.path,
                      copyable: session.path.isNotEmpty,
                    ),
                    InfoRow(
                      label: '远端地址',
                      value: session.remoteAddr,
                      copyable: session.remoteAddr.isNotEmpty,
                      monospace: true,
                    ),
                    if (session.user.isNotEmpty)
                      InfoRow(label: '认证用户', value: session.user),
                    if (session.transport.isNotEmpty)
                      InfoRow(label: '传输', value: session.transport),
                    if (session.userAgent.isNotEmpty)
                      InfoRow(label: 'User-Agent', value: session.userAgent),
                    InfoRow(
                      label: '创建时间',
                      value: session.created == null
                          ? '—'
                          : formatDateTime(session.created!),
                    ),
                    InfoRow(
                      label: '到期时间',
                      value: session.expiresAt == null
                          ? '—'
                          : formatDateTime(session.expiresAt!),
                    ),
                    InfoRow(label: '持续时长', value: session.durationLabel),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SurfaceCard(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Expanded(
                      child: _TrafficValue(
                        label: '入站',
                        value: formatBytes(session.inboundBytes),
                        color: colors.chartIn,
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    Container(width: 1, height: 34, color: colors.border),
                    Expanded(
                      child: _TrafficValue(
                        label: '出站',
                        value: formatBytes(session.outboundBytes),
                        color: colors.chartOut,
                        icon: Icons.north_east_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onKick,
                  style: FilledButton.styleFrom(backgroundColor: colors.danger),
                  icon: const Icon(Icons.link_off_rounded, size: 19),
                  label: const Text('强制断开会话'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '断开后客户端需要重新连接',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
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

class _TrafficValue extends StatelessWidget {
  const _TrafficValue({
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
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colors.textTertiary, fontSize: 9),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}
