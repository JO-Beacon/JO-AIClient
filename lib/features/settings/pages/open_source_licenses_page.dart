import 'package:flutter/foundation.dart' show LicenseEntry, LicenseRegistry;
import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_semantic_colors.dart';

/// 一条按包名合并后的第三方许可记录。
class OpenSourceLicenseGroup {
  const OpenSourceLicenseGroup({required this.packageName, required this.text});

  final String packageName;
  final String text;
}

/// 把 [LicenseRegistry] 的条目合并成「按包名分组」的列表。
///
/// 同一个包可能登记多条条目（每个许可证文件一条），这里按包名合并成一条并按
/// 包名排序，便于查找。Flutter 会把全部 Dart 与平台依赖的许可证预先登记进
/// [LicenseRegistry]，所以这个列表就是随包分发的第三方声明全集。
Future<List<OpenSourceLicenseGroup>> loadOpenSourceLicenses() async {
  final Map<String, StringBuffer> byPackage = <String, StringBuffer>{};
  await for (final LicenseEntry entry in LicenseRegistry.licenses) {
    for (final String package in entry.packages) {
      final buffer = byPackage.putIfAbsent(package, StringBuffer.new);
      for (final paragraph in entry.paragraphs) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(paragraph.text);
      }
    }
  }
  final names = byPackage.keys.toList()..sort();
  return <OpenSourceLicenseGroup>[
    for (final name in names)
      OpenSourceLicenseGroup(
        packageName: name,
        text: byPackage[name]!.toString(),
      ),
  ];
}

/// 许可条目列表。移动端页面与桌面端面板共用，保证两处观感一致。
class OpenSourceLicensesList extends StatelessWidget {
  const OpenSourceLicensesList({
    super.key,
    required this.groups,
    required this.onSelect,
  });

  final List<OpenSourceLicenseGroup> groups;
  final ValueChanged<OpenSourceLicenseGroup> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.aboutOpenSourceLicensesEmpty,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _LicenseRow(
            label: group.packageName,
            onTap: () => onSelect(group),
          ),
        );
      },
    );
  }
}

/// 单条许可的正文。不做排版处理：许可证原文必须按原样呈现。
class OpenSourceLicenseText extends StatelessWidget {
  const OpenSourceLicenseText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SelectableText(
        text,
        style: TextStyle(fontSize: 12.5, height: 1.65, color: cs.onSurface),
      ),
    );
  }
}

/// 与「关于」页同一套 iOS 风格的列表行（卡片底 + 发丝描边 + 右箭头）。
class _LicenseRow extends StatelessWidget {
  const _LicenseRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      baseColor: context.appColors.surfaceCard,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
        width: 0.6,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Lucide.ChevronRight,
            size: 16,
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

/// 「开放源代码许可」页。
///
/// 不用 Flutter 自带的 `showLicensePage`：那个页面是 Material 一套（自带的
/// AppBar、ListTile 与排版），与本应用的界面语言不一致。
///
/// [embedded] 为真时按桌面设置面板的约定渲染：自带一行页头（返回 + 标题），
/// 由调用方放进设置面板的区域里翻页，而不是弹出对话框；为假时是移动端的整页。
class OpenSourceLicensesPage extends StatefulWidget {
  const OpenSourceLicensesPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<OpenSourceLicensesPage> createState() => _OpenSourceLicensesPageState();
}

class _OpenSourceLicensesPageState extends State<OpenSourceLicensesPage> {
  late final Future<List<OpenSourceLicenseGroup>> _licenses;
  OpenSourceLicenseGroup? _selected;

  @override
  void initState() {
    super.initState();
    // 只取一次：许可证列表在进程内不会变，放进 build 会每次重建都重跑。
    _licenses = loadOpenSourceLicenses();
  }

  /// 有选中条目时先退回列表，否则退回上一页。
  void _back() {
    if (_selected != null) {
      setState(() => _selected = null);
      return;
    }
    Navigator.of(context).maybePop();
  }

  Widget _buildContent() {
    return FutureBuilder<List<OpenSourceLicenseGroup>>(
      future: _licenses,
      builder: (context, snapshot) {
        final groups = snapshot.data;
        if (groups == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final selected = _selected;
        if (selected != null) {
          return OpenSourceLicenseText(text: selected.text);
        }
        return OpenSourceLicensesList(
          groups: groups,
          onSelect: (group) => setState(() => _selected = group),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = _selected?.packageName ?? l10n.aboutPageOpenSourceLicenses;
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EmbeddedHeader(title: title, onBack: _back, canPop: true),
          Expanded(child: _buildContent()),
        ],
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          size: 20,
          padding: const EdgeInsets.all(8),
          minSize: 40,
          color: cs.onSurface,
          semanticLabel: l10n.settingsPageBackButton,
          tooltip: l10n.settingsPageBackButton,
          onTap: _back,
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: const [SizedBox(width: 12)],
      ),
      body: _buildContent(),
    );
  }
}

/// 桌面设置面板里的页头，与仓库既有嵌入式页（如定时任务）保持一致。
class _EmbeddedHeader extends StatelessWidget {
  const _EmbeddedHeader({
    required this.title,
    required this.onBack,
    required this.canPop,
  });

  final String title;
  final VoidCallback onBack;
  final bool canPop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bar = theme.appBarTheme;
    final cs = theme.colorScheme;
    return Container(
      height: bar.toolbarHeight ?? kToolbarHeight,
      color: bar.backgroundColor ?? cs.surface,
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Center(
              child: IosIconButton(
                icon: Lucide.ArrowLeft,
                size: 22,
                minSize: 44,
                color: bar.foregroundColor ?? cs.onSurface,
                enabled: canPop,
                semanticLabel: AppLocalizations.of(
                  context,
                )!.settingsPageBackButton,
                onTap: onBack,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bar.titleTextStyle ?? theme.textTheme.titleLarge,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}
