import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/json_diff.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_exception.dart';
import '../../state/app_state.dart';

enum ConfigKind { global, pathDefaults }

extension ConfigKindX on ConfigKind {
  String get title => switch (this) {
    ConfigKind.global => '全局配置',
    ConfigKind.pathDefaults => '路径默认值',
  };

  String get subtitle => switch (this) {
    ConfigKind.global => 'MediaMTX 运行时全局参数，修改会立即生效',
    ConfigKind.pathDefaults => '新建路径时继承的默认参数',
  };
}

class ConfigViewerScreen extends StatefulWidget {
  const ConfigViewerScreen({super.key, required this.kind});

  final ConfigKind kind;

  @override
  State<ConfigViewerScreen> createState() => _ConfigViewerScreenState();
}

class _ConfigViewerScreenState extends State<ConfigViewerScreen> {
  final _json = TextEditingController();
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _config = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
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
      final config = switch (widget.kind) {
        ConfigKind.global => await service.globalConfig(),
        ConfigKind.pathDefaults => await service.pathDefaults(),
      };
      if (!mounted) return;
      setState(() {
        _config = config;
        _json.text = const JsonEncoder.withIndent('  ').convert(config);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.friendlyMessage);
    } catch (error) {
      if (mounted) setState(() => _error = '加载配置失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(_json.text);
      if (decoded is! Map) {
        setState(() => _error = '配置必须是一个 JSON 对象');
        return;
      }
      parsed = Map<String, dynamic>.from(decoded);
    } on FormatException catch (error) {
      setState(() => _error = 'JSON 格式错误：${error.message}');
      return;
    }
    final diff = changedTopLevelKeys(_config, parsed);
    if (diff.isEmpty) {
      setState(() => _error = '配置没有变化');
      return;
    }
    if (containsRedactedSecret(diff)) {
      setState(() => _error = '修改内容包含服务端脱敏字段（<redacted>），请通过「访问控制」页面管理用户密码');
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '应用配置更改？',
      message: '将提交 ${diff.length} 个变更字段，PATCH 到服务端并立即生效。错误的参数可能中断正在进行的流。',
      confirmLabel: '应用',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final app = context.read<AppState>();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      switch (widget.kind) {
        case ConfigKind.global:
          await app.requireService.patchGlobalConfig(diff);
        case ConfigKind.pathDefaults:
          await app.requireService.patchPathDefaults(diff);
      }
      if (!mounted) return;
      showAppSnack(context, '配置已更新');
      setState(() => _editing = false);
      await app.loadGlobalConfig();
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.friendlyMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind.title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新加载',
          ),
          IconButton(
            onPressed: () => copyText(context, _json.text),
            icon: const Icon(Icons.copy_rounded),
            tooltip: '复制 JSON',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackdrop(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
          child: ContentWidth(
            maxWidth: 1600,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.kind.subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: colors.warning.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 17,
                        color: colors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '敏感字段会以明文显示。请勿在不可信设备上编辑生产配置。',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.warning,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ErrorBanner(
                    message: _error!,
                    onClose: () => setState(() => _error = null),
                  ),
                ],
                const SizedBox(height: 14),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  )
                else if (_editing)
                  TextField(
                    controller: _json,
                    maxLines: null,
                    minLines: 22,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.55,
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      labelText: 'Config JSON',
                    ),
                  )
                else
                  CodeBlock(
                    code: _json.text.isEmpty ? '{}' : _json.text,
                    onCopy: () => copyText(context, _json.text),
                  ),
              ],
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
          child: _editing
              ? Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _editing = false;
                          _json.text = const JsonEncoder.withIndent('  ')
                              .convert(_config);
                          _error = null;
                        }),
                        child: const Text('取消编辑'),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                            : const Text('应用配置'),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _editing = true),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('编辑 JSON'),
                  ),
                ),
        ),
      ),
    );
  }
}
