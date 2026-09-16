import 'package:flutter/cupertino.dart';

import '../../../../core/constants/app_constants.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final bool showTitleChevron;
  final VoidCallback? onTitleTap;

  const SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.showTitleChevron = false,
    this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final titleWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: isDark ? CupertinoColors.white : CupertinoColors.black,
          ),
        ),
        if (showTitleChevron) ...[
          const SizedBox(width: 4),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: isDark
                ? CupertinoColors.white.withOpacity(0.60)
                : CupertinoColors.secondaryLabel,
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onTitleTap != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: onTitleTap,
              child: titleWidget,
            )
          else
            titleWidget,
          if (onSeeAll != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: onSeeAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? CupertinoColors.white.withOpacity(0.60)
                          : CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 13,
                    color: isDark
                        ? CupertinoColors.white.withOpacity(0.60)
                        : CupertinoColors.secondaryLabel,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
