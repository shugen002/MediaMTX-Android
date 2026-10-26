import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_exception.dart';
import '../../state/app_state.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = const [];
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
      final users = await service.internalUsers();
      if (mounted) setState(() => _users = users);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.friendlyMessage);
    } catch (error) {
      if (mounted) setState(() => _error = '加载用户失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _AddUserSheet(),
    );
    if (result == null || !mounted) return;
    final app = context.read<AppState>();
    try {
      await app.requireService.addInternalUser(result);
      if (!mounted) return;
      showAppSnack(context, '用户已添加');
      await _load();
    } on ApiException catch (error) {
      if (mounted) showAppSnack(context, error.friendlyMessage, error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> user) async {
    final name = (user['user'] ?? '').toString();
    if (name == 'any') {
      showAppSnack(context, '内置 any 用户不能删除', error: true);
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '删除用户「$name」？',
      message: '删除后，使用该账号的客户端将无法通过认证。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final app = context.read<AppState>();
    try {
      await app.requireService.deleteInternalUser(
        (user['id'] ?? '').toString(),
      );
      if (!mounted) return;
      showAppSnack(context, '用户已删除');
      await _load();
    } on ApiException catch (error) {
      if (mounted) showAppSnack(context, error.friendlyMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final currentUser = app.active?.username ?? '';
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('访问控制'),
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
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 116),
            child: ContentWidth(
              maxWidth: 1600,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '管理 MediaMTX 内置用户。修改会立即写入服务端配置。',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
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
                  else if (_users.isEmpty)
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: EmptyState(
                        icon: Icons.group_outlined,
                        title: '没有内部用户',
                        message: '服务端可能使用 HTTP 或 JWT 认证，而不是 internal。',
                        action: FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('添加用户'),
                        ),
                      ),
                    )
                  else
                    ..._users.map(
                      (user) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _UserCard(
                          user: user,
                          isCurrent:
                              (user['user'] ?? '').toString() == currentUser,
                          onDelete: () => _delete(user),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('添加用户'),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onDelete,
    this.isCurrent = false,
  });

  final Map<String, dynamic> user;
  final VoidCallback onDelete;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final name = (user['user'] ?? '').toString();
    final ips = user['ips'];
    final permissions = user['permissions'];
    final actions = <String>[];
    if (permissions is List) {
      for (final item in permissions.whereType<Map>()) {
        actions.add((item['action'] ?? '').toString());
      }
    }
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (name == 'any' ? colors.warning : colors.chartIn)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              name == 'any' ? Icons.public_rounded : Icons.person_rounded,
              size: 19,
              color: name == 'any' ? colors.warning : colors.chartIn,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (name == 'any') ...[
                      const SizedBox(width: 6),
                      StatusPill(
                        label: '匿名',
                        color: colors.warning,
                        dense: true,
                      ),
                    ] else if (isCurrent) ...[
                      const SizedBox(width: 6),
                      StatusPill(
                        label: '当前账号',
                        color: colors.success,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final action in actions)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceHigh,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          action,
                          style: textTheme.labelSmall?.copyWith(
                            fontSize: 8.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                if (ips is List && ips.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    'IP: ${ips.join(', ')}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (name != 'any' && !isCurrent)
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 19,
                color: colors.danger.withValues(alpha: 0.8),
              ),
              tooltip: '删除用户',
            ),
        ],
      ),
    );
  }
}

class _AddUserSheet extends StatefulWidget {
  const _AddUserSheet();

  @override
  State<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends State<_AddUserSheet> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _ips = TextEditingController();
  final Set<String> _permissions = {'read', 'publish'};
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _ips.dispose();
    super.dispose();
  }

  void _submit() {
    final user = _user.text.trim();
    if (user.isEmpty) {
      setState(() => _error = '请输入用户名');
      return;
    }
    if (user == 'any') {
      setState(() => _error = 'any 是内置匿名用户，不可重复创建');
      return;
    }
    if (_pass.text.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    if (_permissions.isEmpty) {
      setState(() => _error = '至少选择一项权限');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'user': user,
      'pass': _pass.text,
      'ips': _ips.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      'permissions': [
        for (final action in _permissions) {'action': action, 'path': ''},
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '添加内部用户',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '权限会立即写入服务端的 authInternalUsers。',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _user,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pass,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ips,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '允许的 IP（可选，逗号分隔）',
                  hintText: '192.168.1.0/24, 10.0.0.5',
                  prefixIcon: Icon(Icons.lan_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '权限',
                style: textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final action in ['read', 'publish', 'api', 'playback'])
                    FilterChip(
                      label: Text(action),
                      selected: _permissions.contains(action),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _permissions.add(action);
                          } else {
                            _permissions.remove(action);
                          }
                        });
                      },
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(color: colors.danger),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('创建用户'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
