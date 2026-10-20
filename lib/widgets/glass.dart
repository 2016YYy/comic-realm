import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';

/// 当前是否启用毛玻璃效果。集中一处，方便各界面查询。
bool glassEnabled(BuildContext context) =>
    context.watch<SettingsService>().glassEffect;

/// 玻璃叠色：浅色下略偏白、深色下略偏浅的主题表面色。
Color glassTint(BuildContext context, {double? darkAlpha, double? lightAlpha}) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final alpha = isDark ? (darkAlpha ?? 0.45) : (lightAlpha ?? 0.55);
  return (isDark ? scheme.surface : Colors.white).withValues(alpha: alpha);
}

/// Liquid Glass 表面：ClipRRect + BackdropFilter 真实模糊 + 半透明叠色 + 高光描边。
///
/// 只用于**悬浮在内容之上**的区域（顶栏、底栏、弹窗、抽屉、菜单）——模糊会
/// 实时采样其背后的画面，从而得到真实的毛玻璃观感。不要用在长列表项上，
/// 那会对滚动内容逐帧模糊、显著掉帧。
class GlassBlur extends StatelessWidget {
  final Widget child;
  final double blur;
  final BorderRadius? borderRadius;
  final Color? tint;
  final bool border;
  final bool clip;

  const GlassBlur({
    super.key,
    required this.child,
    this.blur = 24,
    this.borderRadius,
    this.tint,
    this.border = true,
    this.clip = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.zero;
    final decoration = BoxDecoration(
      color: tint ?? glassTint(context),
      borderRadius: radius,
      border: border
          ? Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : scheme.primary.withValues(alpha: 0.10),
              width: 0.8,
            )
          : null,
    );

    Widget body = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: DecoratedBox(decoration: decoration, child: child),
    );
    // 裁剪必须在 BackdropFilter 之外，否则模糊会溢出圆角。
    if (clip) {
      body = ClipRRect(borderRadius: radius, child: body);
    }
    return RepaintBoundary(child: body);
  }
}

/// 毛玻璃顶栏：透明 AppBar + BackdropFilter 背景，兼容 TabBar([bottom]) 与自定义动作。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;
  final bool centerTitle;
  final bool automaticallyImplyLeading;
  final bool showBottomBorder;

  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
    this.centerTitle = false,
    this.automaticallyImplyLeading = true,
    this.showBottomBorder = true,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    if (!glassEnabled(context)) {
      return AppBar(
        title: title,
        actions: actions,
        leading: leading,
        bottom: bottom,
        toolbarHeight: toolbarHeight,
        centerTitle: centerTitle,
        automaticallyImplyLeading: automaticallyImplyLeading,
      );
    }
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: title,
      actions: actions,
      leading: leading,
      bottom: bottom,
      toolbarHeight: toolbarHeight,
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
      flexibleSpace: GlassBlur(
        blur: 24,
        border: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: showBottomBorder
                ? Border(bottom: BorderSide(color: Theme.of(context).dividerColor))
                : null,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
