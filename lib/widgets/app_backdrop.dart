import 'dart:ui';

import 'package:flutter/material.dart';

/// 应用级装饰背景：主题种子色的柔和渐变 + 两团模糊光斑。
///
/// 毛玻璃层（顶栏 / 底栏 / 弹窗 / 抽屉）会实时模糊它，从而得到真实、统一、
/// 且**不随列表滚动变化**的 Liquid Glass 观感——既好看又不会因逐帧模糊滚动
/// 内容而掉帧。整层用 RepaintBoundary 缓存，几乎不产生额外重绘。
class AppBackdrop extends StatelessWidget {
  final Widget child;

  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = scheme.surface;
    final top = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.16 : 0.10),
      base,
    );
    final bottom = Color.alphaBlend(
      scheme.tertiary.withValues(alpha: isDark ? 0.14 : 0.09),
      base,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [top, base, bottom],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -90,
                  right: -70,
                  child: _Blob(
                    color: scheme.primary,
                    size: 240,
                    alpha: isDark ? 0.38 : 0.30,
                  ),
                ),
                Positioned(
                  bottom: -70,
                  left: -80,
                  child: _Blob(
                    color: scheme.tertiary,
                    size: 280,
                    alpha: isDark ? 0.32 : 0.26,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 内容层盖在背景之上，正常接收点击
        Positioned.fill(child: child),
      ],
    );
  }
}

/// 模糊光斑：层层叠加的柔和色团，让毛玻璃模糊后呈现流动色块而非单调平面。
class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  final double alpha;

  const _Blob({required this.color, required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: alpha),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
