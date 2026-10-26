import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/json_diff.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/path_config.dart';
import '../../state/app_state.dart';

class PathEditorScreen extends StatefulWidget {
  const PathEditorScreen({super.key, this.pathName, this.config});

  final String? pathName;
  final PathConfig? config;

  @override
  State<PathEditorScreen> createState() => _PathEditorScreenState();
}

class _PathEditorScreenState extends State<PathEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _source;
  late final TextEditingController _recordPath;
  late final TextEditingController _maxReaders;
  late final TextEditingController _runOnDemand;
  late final TextEditingController _json;
  late bool _alwaysAvailable;
  late bool _sourceOnDemand;
  late bool _record;
  bool _advanced = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.config != null;
  bool get _nameLocked => widget.pathName != null;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    final name = widget.pathName ?? config?.name ?? '';
    _name = TextEditingController(text: name);
    _source = TextEditingController(text: config?.source ?? '');
    _recordPath = TextEditingController(text: config?.recordPath ?? '');
    _maxReaders = TextEditingController(
      text: (config?.maxReaders ?? 0) == 0 ? '' : '${config!.maxReaders}',
    );
    _runOnDemand = TextEditingController(text: config?.runOnDemand ?? '');
    _alwaysAvailable = config?.alwaysAvailable ?? false;
    _sourceOnDemand = config?.sourceOnDemand ?? false;
    _record = config?.record ?? false;
    _json = TextEditingController(
      text: const JsonEncoder.withIndent('  ')
          .convert(config?.raw ?? <String, dynamic>{}),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _source.dispose();
    _recordPath.dispose();
    _maxReaders.dispose();
    _runOnDemand.dispose();
    _json.dispose();
    super.dispose();
  }

  Map<String, dynamic> _formMap() {
    final source = _source.text.trim();
    final map = <String, dynamic>{
      if (source.isNotEmpty) 'source': source,
      'alwaysAvailable': _alwaysAvailable,
      'sourceOnDemand': _sourceOnDemand,
      'record': _record,
      'maxReaders': int.tryParse(_maxReaders.text.trim()) ?? 0,
    };
    if (_record) {
      map['recordPath'] = _recordPath.text.trim();
    }
    final runOnDemand = _runOnDemand.text.trim();
    if (runOnDemand.isNotEmpty) {
      map['runOnDemand'] = runOnDemand;
    }
    return map;
  }

  void _toggleAdvanced() {
    if (!_advanced) {
      final base = Map<String, dynamic>.from(widget.config?.raw ?? {})
        ..addAll(_formMap());
      _json.text = const JsonEncoder.withIndent('  ').convert(base);
    }
    setState(() {
      _advanced = !_advanced;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_advanced && !_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    final service = app.service;
    if (service == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入路径名称');
      return;
    }
    Map<String, dynamic> body;
    if (_advanced) {
      try {
        final decoded = jsonDecode(_json.text);
        if (decoded is! Map) {
          setState(() => _error = 'JSON 配置必须是一个对象');
          return;
        }
        body = Map<String, dynamic>.from(decoded)..remove('name');
        if (_editing) {
          body = changedTopLevelKeys(widget.config!.raw, body);
          if (body.isEmpty) {
            setState(() => _error = '配置没有变化');
            return;
          }
        }
        if (containsRedactedSecret(body)) {
          setState(() => _error = '配置包含服务端脱敏字段（<redacted>），不能通过编辑器提交');
          return;
        }
      } on FormatException catch (error) {
        setState(() => _error = 'JSON 格式错误：${error.message}');
        return;
      }
    } else {
      body = _formMap();
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await service.patchPath(name, body);
      } else {
        await service.addPath(name, body);
      }
      if (!mounted) return;
      showAppSnack(context, _editing ? '路径配置已更新' : '路径已保存');
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.friendlyMessage);
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
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
        title: Text(_editing ? '编辑路径' : '新建路径'),
        actions: [
          TextButton.icon(
            onPressed: _toggleAdvanced,
            icon: Icon(
              _advanced ? Icons.list_alt_rounded : Icons.code_rounded,
              size: 17,
            ),
            label: Text(_advanced ? '表单' : 'JSON'),
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
                  if (_error != null) ...[
                    ErrorBanner(
                      message: _error!,
                      onClose: () => setState(() => _error = null),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_advanced) ...[
                    Text(
                      'JSON 配置会直接发送到服务端。编辑时可保留表单未覆盖的高级字段。',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _json,
                      maxLines: null,
                      minLines: 16,
                      style: textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.55,
                        fontSize: 12,
                      ),
                      decoration: const InputDecoration(
                        alignLabelWithHint: true,
                        labelText: 'PathConf JSON',
                      ),
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _name,
                      enabled: !_nameLocked,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: '路径名称',
                        hintText: '例如：live、camera-01',
                        prefixIcon: const Icon(Icons.route_rounded),
                        helperText: _nameLocked
                            ? '路径名称创建后不可修改'
                            : '推流地址中的路径名，例如 rtmp://host/live',
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? '请输入路径名称' : null,
                    ),
                    const SizedBox(height: 16),
                    const TechLabel('来源'),
                    const SizedBox(height: 9),
                    TextFormField(
                      controller: _source,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '拉流地址（可选）',
                        hintText: 'rtsp://user:pass@host/stream',
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) return null;
                        final uri = Uri.tryParse(text);
                        if (uri == null || uri.scheme.isEmpty) {
                          return '请输入完整 URL，或留空以接受推流';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '留空时路径等待外部推流；填写后会主动拉流。支持 RTSP、RTMP、SRT、HLS、RTP 等。',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SurfaceCard(
                      padding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('常驻可用'),
                            subtitle: const Text('即使没有发布者，也保持路径和轨道可用'),
                            value: _alwaysAvailable,
                            onChanged: (value) =>
                                setState(() => _alwaysAvailable = value),
                          ),
                          Divider(color: colors.border, height: 1),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('按需拉流'),
                            subtitle: const Text('只有观看者进入时才连接来源'),
                            value: _sourceOnDemand,
                            onChanged: (value) =>
                                setState(() => _sourceOnDemand = value),
                          ),
                          Divider(color: colors.border, height: 1),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('录制'),
                            subtitle: const Text('将流保存到服务端磁盘'),
                            value: _record,
                            onChanged: (value) =>
                                setState(() => _record = value),
                          ),
                        ],
                      ),
                    ),
                    if (_record) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _recordPath,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '录制路径模板（可选）',
                          hintText: 'recordings/%path/%Y-%m-%d_%H-%M-%S-%f',
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const TechLabel('限制与钩子'),
                    const SizedBox(height: 9),
                    TextFormField(
                      controller: _maxReaders,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '最大观看者数',
                        hintText: '留空或 0 表示不限制',
                        prefixIcon: Icon(Icons.groups_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _runOnDemand,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '按需启动命令（可选）',
                        hintText: 'ffmpeg -i ... -c copy -f rtsp rtsp://localhost/\$MTX_PATH',
                        prefixIcon: Icon(Icons.terminal_rounded),
                      ),
                      maxLines: 2,
                      minLines: 1,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '命令在服务端执行。修改会立即生效，不会中断当前推流。',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
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
          child: SizedBox(
            width: double.infinity,
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
                  : Text(_editing ? '保存修改' : '创建路径'),
            ),
          ),
        ),
      ),
    );
  }
}
