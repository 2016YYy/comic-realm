import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 统一的漫画封面组件：圆角 + 占位 + 加载失败兜底。
/// 全应用只在这里处理封面加载，避免各页面各写一套。
class ComicCover extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;

  const ComicCover({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.radius = 14,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? _placeholder(scheme, Icons.image_not_supported_outlined)
            : CachedNetworkImage(
                imageUrl: url,
                fit: fit,
                width: width,
                height: height,
                // 很多图源开启了防盗链，直接请求图片会被 403，
                // 这里按图片自身域名补一个 Referer 头即可正常显示。
                httpHeaders: imageHeaders(url),
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => _placeholder(scheme, null),
                errorWidget: (_, __, ___) =>
                    _placeholder(scheme, Icons.broken_image_outlined),
              ),
      ),
    );
  }

  /// 依据图片地址推导同源 Referer，用于绕过常见防盗链。
  static Map<String, String>? imageHeaders(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) return null;
      return {'Referer': '${uri.scheme}://${uri.host}/'};
    } catch (_) {
      return null;
    }
  }

  Widget _placeholder(ColorScheme scheme, IconData? icon) {
    return Container(
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: icon == null
          ? null
          : Icon(icon, size: 28, color: scheme.onSurfaceVariant),
    );
  }
}

/// 网格/列表中展示「来源图源」的小标签
class SourceBadge extends StatelessWidget {
  final String label;

  const SourceBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }
}
