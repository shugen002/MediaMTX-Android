import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/url_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_exception.dart';
import '../../data/api/mediamtx_service.dart';
import '../../data/models/server_profile.dart';
import '../../state/app_state.dart';

class ServerFormScreen extends StatefulWidget {
  const ServerFormScreen({super.key, this.profile});

  final ServerProfile? profile;

  @override
  State<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends State<ServerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _secret;
  late ServerAuthMethod _auth;
  late bool _allowSelfSigned;
  bool _showSecret = false;
  bool _testing = false;
  bool _saving = false;
  String? _testError;
  String? _testSuccess;

  bool get _editing => widget.profile != null;
  bool get _isLocal => widget.profile?.isLocal ?? false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile?.name ?? '');
    _url = TextEditingController(text: profile?.baseUrl ?? '');
    _username = TextEditingController(text: profile?.username ?? '');
    _secret = TextEditingController();
    _auth = profile?.authMethod ?? ServerAuthMethod.none;
    _allowSelfSigned = profile?.allowSelfSigned ?? false;
    if (profile != null && profile.authMethod != ServerAuthMethod.none) {
      _loadSecret(profile.id);
    }
  }

  Future<void> _loadSecret(String id) async {
    final secret = await context.read<AppState>().readSecret(id);
    if (mounted && secret != null) {
      setState(() => _secret.text = secret);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _secret.dispose();
    super.dispose();
  }

  String get _normalizedUrl => normalizeBaseUrl(_url.text);

  ServerProfile _buildProfile() {
    final profile = widget.profile;
    return ServerProfile(
      id: profile?.id ?? ServerProfile.newId(),
      name: _name.text.trim().isEmpty
          ? hostWithPort(
              ServerProfile(
                id: 'preview',
                name: '',
                baseUrl: _normalizedUrl,
                createdAt: DateTime.now(),
              ),
            )
          : _name.text.trim(),
      baseUrl: _isLocal ? profile!.baseUrl : _normalizedUrl,
      username: _isLocal
          ? profile!.username
          : (_auth == ServerAuthMethod.none ? '' : _username.text.trim()),
      authMethod: _isLocal ? profile!.authMethod : _auth,
      isLocal: profile?.isLocal ?? false,
      allowSelfSigned: _isLocal ? profile!.allowSelfSigned : _allowSelfSigned,
      createdAt: profile?.createdAt ?? DateTime.now(),
      lastConnectedAt: profile?.lastConnectedAt,
    );
  }

  Future<void> _testConnection() async {
    if (!_validate()) return;
    setState(() {
      _testing = true;
      _testError = null;
      _testSuccess = null;
    });
    final profile = _buildProfile();
    final client = ApiClient(
      baseUrl: profile.baseUrl,
      authMethod: _auth,
      username: _username.text.trim(),
      secret: _secret.text,
      allowBadCertificates: _allowSelfSigned,
      timeout: const Duration(seconds: 8),
    );
    try {
      final info = await MediaMtxService(client).info();
      if (!mounted) return;
      setState(() {
        _testSuccess = '连接成功 · ${info.version} · 已运行 ${info.uptimeLabel}';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _testError = error.friendlyMessage);
    } catch (error) {
      if (!mounted) return;
      setState(() => _testError = '连接失败：$error');
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  bool _validate() {
    if (!_formKey.currentState!.validate()) return false;
    if (_isLocal) return true;
    if (_auth != ServerAuthMethod.none &&
        _auth == ServerAuthMethod.basic &&
        _username.text.trim().isEmpty) {
      setState(() => _testError = '请输入用户名');
      return false;
    }
    if (_auth != ServerAuthMethod.none && _secret.text.isEmpty) {
      setState(
        () => _testError = _auth == ServerAuthMethod.basic
            ? '请输入密码'
            : '请输入 Bearer Token',
      );
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final app = context.read<AppState>();
    final profile = _buildProfile();
    setState(() {
      _saving = true;
      _testError = null;
    });
    await app.saveServer(profile, secret: _isLocal ? null : _secret.text);
    if (app.active?.id == profile.id) {
      await app.connect(profile, silent: true);
    }
    if (!mounted) return;
    Navigator.pop(context, profile);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑服务器' : '添加服务器'),
        actions: [
          IconButton(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_rounded),
            tooltip: '测试连接',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AppBackdrop(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 130),
            child: ContentWidth(
              maxWidth: 620,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SurfaceCard(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(Icons.dns_rounded, color: scheme.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '连接到 MediaMTX',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '填写 Control API 地址。默认端口为 9997。',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isLocal) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: colors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: colors.success.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.smartphone_rounded,
                            size: 17,
                            color: colors.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '本机服务由 App 托管，API 地址和凭据会自动维护；此处仅修改显示名称。',
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.success,
                                fontSize: 10.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const TechLabel('基本信息'),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '显示名称',
                      hintText: '例如：家中服务器',
                      prefixIcon: Icon(Icons.label_outline_rounded),
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? '请输入名称' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _url,
                    enabled: !_isLocal,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'API 地址',
                      hintText: 'http://192.168.1.10:9997',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    validator: (value) =>
                        _isLocal ? null : validateBaseUrl(value ?? ''),
                    onChanged: (_) {
                      if (_testError != null || _testSuccess != null) {
                        setState(() {
                          _testError = null;
                          _testSuccess = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持 http:// 或 https://，可带反向代理路径；会自动移除末尾 /v3。',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const TechLabel('认证方式'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final method in ServerAuthMethod.values)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: method == ServerAuthMethod.values.last
                                  ? 0
                                  : 8,
                            ),
                            child: _AuthChoice(
                              label: switch (method) {
                                ServerAuthMethod.none => '无认证',
                                ServerAuthMethod.basic => 'Basic',
                                ServerAuthMethod.bearer => 'Token',
                              },
                              selected: _auth == method,
                              enabled: !_isLocal,
                              onTap: _isLocal
                                  ? null
                                  : () => setState(() {
                                      _auth = method;
                                      _testError = null;
                                      _testSuccess = null;
                                    }),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_auth != ServerAuthMethod.none) ...[
                    const SizedBox(height: 14),
                    if (_auth == ServerAuthMethod.basic)
                      TextFormField(
                        controller: _username,
                        enabled: !_isLocal,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ? '请输入用户名' : null,
                      ),
                    if (_auth == ServerAuthMethod.basic)
                      const SizedBox(height: 12),
                    TextFormField(
                      controller: _secret,
                      enabled: !_isLocal,
                      obscureText: !_showSecret,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: _auth == ServerAuthMethod.basic
                            ? '密码'
                            : 'Bearer Token',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _showSecret = !_showSecret),
                          icon: Icon(
                            _showSecret
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                      validator: (value) => (value ?? '').isEmpty
                          ? (_auth == ServerAuthMethod.basic
                                ? '请输入密码'
                                : '请输入 Token')
                          : null,
                    ),
                  ],
                  if (_normalizedUrl.startsWith('https://')) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('允许自签名证书', style: textTheme.titleSmall),
                      subtitle: Text(
                        '仅在你信任该服务器时开启',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      value: _allowSelfSigned,
                      onChanged: (value) =>
                          setState(() => _allowSelfSigned = value),
                    ),
                  ],
                  if (_testError != null) ...[
                    const SizedBox(height: 14),
                    ErrorBanner(message: _testError!),
                  ],
                  if (_testSuccess != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: colors.success.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colors.success.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: colors.success,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _testSuccess!,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const _ApiHelpCard(),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.background.withValues(alpha: 0.96),
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing || _saving ? null : _testConnection,
                  child: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('保存并连接'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthChoice extends StatelessWidget {
  const _AuthChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : colors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? scheme.primary : colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiHelpCard extends StatelessWidget {
  const _ApiHelpCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: colors.textSecondary,
          collapsedIconColor: colors.textTertiary,
          title: Text(
            '如何启用 Control API？',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          children: [
            Text(
              '在 MediaMTX 的 mediamtx.yml 中启用 API，然后重启服务：',
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 10),
            const CodeBlock(
              code:
                  'api: yes\n'
                  'apiAddress: :9997\n'
                  'apiAllowOrigins: [\'*\']',
              onCopy: null,
            ),
            const SizedBox(height: 10),
            Text(
              '若使用 Docker，请映射 9997 端口，并确保手机能访问服务器。',
              style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
