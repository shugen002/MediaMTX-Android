import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/local/local_server_controller.dart';

class LocalLogsScreen extends StatefulWidget {
  const LocalLogsScreen({super.key});

  @override
  State<LocalLogsScreen> createState() => _LocalLogsScreenState();
}

class _LocalLogsScreenState extends State<LocalLogsScreen> {
  final _scroll = ScrollController();
  Timer? _timer;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh(scrollToEnd: true);
      _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        if (mounted && _autoScroll) _refresh(scrollToEnd: true);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool scrollToEnd = false}) async {
    final local = context.read<LocalServerController>();
    await local.loadLogs();
    if (!mounted || !scrollToEnd) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final local = context.watch<LocalServerController>();
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final logs = local.logs.trim();
    final lineCount = logs.isEmpty ? 0 : '\n'.allMatches(logs).length + 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务日志'),
        actions: [
          IconButton(
            onPressed: () => _refresh(scrollToEnd: true),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
          IconButton(
            onPressed: logs.isEmpty ? null : () => copyText(context, logs),
            icon: const Icon(Icons.copy_rounded),
            tooltip: '复制全部',
          ),
          IconButton(
            onPressed: () async {
              try {
                await context.read<LocalServerController>().shareLog();
              } catch (error) {
                if (context.mounted) {
                  showAppSnack(context, '导出失败：$error', error: true);
                }
              }
            },
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: '导出日志文件',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackdrop(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Row(
                children: [
                  StatusDot(
                    color: local.isRunning
                        ? colors.success
                        : colors.textTertiary,
                    size: 6,
                    pulse: local.isRunning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    local.isRunning ? '服务运行中' : '服务未运行',
                    style: textTheme.labelSmall?.copyWith(
                      color: local.isRunning
                          ? colors.success
                          : colors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$lineCount 行',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _autoScroll = !_autoScroll),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _autoScroll
                            ? colors.success.withValues(alpha: 0.1)
                            : colors.surfaceHigh,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _autoScroll
                                ? Icons.vertical_align_bottom_rounded
                                : Icons.pause_rounded,
                            size: 12,
                            color: _autoScroll
                                ? colors.success
                                : colors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _autoScroll ? '自动滚动' : '已暂停',
                            style: textTheme.labelSmall?.copyWith(
                              color: _autoScroll
                                  ? colors.success
                                  : colors.textTertiary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: colors.isDark
                      ? const Color(0xFF060A0F)
                      : const Color(0xFFF0F4FA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: logs.isEmpty
                    ? Center(
                        child: Text(
                          '暂无日志\n启动本机服务后会显示 MediaMTX 输出',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textTertiary,
                            height: 1.6,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        controller: _scroll,
                        child: SelectableText(
                          logs,
                          style: textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            height: 1.65,
                            color: colors.isDark
                                ? const Color(0xFFB9D2F2)
                                : const Color(0xFF24405F),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
