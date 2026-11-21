import 'package:flutter/material.dart';
import '../services/avatars.dart';

/// 디자인 시안의 색. 밝은 민트 배경 위에 흰 카드, 청록색 강조.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF14A08B);
  static const primaryDark = Color(0xFF0E8573);
  static const mint = Color(0xFFDDF4EF);
  static const mintSoft = Color(0xFFEFF9F6);
  static const background = Color(0xFFF4FAF9);
  static const ink = Color(0xFF1C2B29);
  static const sub = Color(0xFF6B7C79);
  static const line = Color(0xFFE3ECEA);
  static const online = Color(0xFF2E9E5B);
  static const onlineBg = Color(0xFFE1F4E8);
  static const offline = Color(0xFF9AA8A5);
  static const me = Color(0xFF33485C);
  static const place = Color(0xFF8C9A97);
  static const danger = Color(0xFFE5484D);

  static const shadow = [
    BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 4)),
  ];
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: Colors.white,
    onSurface: AppColors.ink,
  );
  final stadium = const StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Pretendard',
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      titleTextStyle: TextStyle(
          fontFamily: 'Pretendard', fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.primary),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: stadium,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: stadium,
        minimumSize: const Size(64, 52),
        foregroundColor: AppColors.primaryDark,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        textStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : const Color(0xFFD5DEDC)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.mint : Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.primaryDark : AppColors.ink),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
        iconSize: const WidgetStatePropertyAll(16),
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: 'Pretendard', fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(side: BorderSide(color: AppColors.line)),
      backgroundColor: Colors.white,
      selectedColor: AppColors.mint,
      labelStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 15, color: AppColors.ink),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: StadiumBorder(),
    ),
  );
}

/// 한글은 글자 단위로 줄이 바뀌어 "있어\n요" 처럼 끊기므로, 단어 안에서는 줄을 바꾸지 않게 한다.
String keepWords(String text) => text
    .split(' ')
    .map((w) => w.characters.join('\u2060'))
    .join(' ');

/// 화면 위쪽에 떠 있는 둥근 흰색 제목 바 (뒤로가기 · 제목 · 버튼들).
class PillAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PillAppBar({super.key, required this.title, this.leading, this.actions = const []});

  final String title;

  /// 없으면 이전 화면이 있을 때 뒤로가기 버튼을 둔다.
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return SafeArea(
      bottom: false,
      child: PillBar(
        leading: leading ??
            (canPop
                ? IconButton(
                    tooltip: '뒤로',
                    icon: const Icon(Icons.arrow_back, size: 28),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : null),
        title: title,
        actions: actions,
      ),
    );
  }
}

/// [PillAppBar] 의 몸통. 지도 위에 띄울 때는 이것만 쓴다.
class PillBar extends StatelessWidget {
  const PillBar({super.key, required this.title, this.leading, this.actions = const []});

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppColors.shadow,
      ),
      child: Row(
        children: [
          if (leading != null) leading! else const SizedBox(width: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 흰색 둥근 카드 (그림자 포함).
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.only(bottom: 16),
    this.onTap,
    this.color = Colors.white,
    this.border,
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color color;
  final BoxBorder? border;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: shape,
          border: border,
          boxShadow: AppColors.shadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: shape,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// 연한 민트색 동그라미 안의 아이콘.
class IconBubble extends StatelessWidget {
  const IconBubble(this.icon, {super.key, this.size = 56, this.color = AppColors.primary, this.background});

  final IconData icon;
  final double size;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background ?? AppColors.mintSoft),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// 연한 민트색 동그라미 안의 이모지.
class EmojiBubble extends StatelessWidget {
  const EmojiBubble(this.emoji, {super.key, this.size = 56, this.background});

  final String emoji;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background ?? AppColors.mint),
      alignment: Alignment.center,
      child: AvatarGlyph(emoji, size: size * 0.82),
    );
  }
}

/// 왼쪽 청록 막대가 붙은 구역 제목 ("알림", "멤버").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(4, 8, 4, 12)});

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ],
      ),
    );
  }
}

/// 둥근 작은 꼬리표 ("온라인", "방장", "무료 >").
class TagChip extends StatelessWidget {
  const TagChip(
    this.label, {
    super.key,
    this.color = AppColors.primaryDark,
    this.background = AppColors.mint,
    this.dot = false,
    this.trailing,
    this.onTap,
  });

  final String label;
  final Color color;
  final Color background;
  final bool dot;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 5),
          ],
          Text(label, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
          if (trailing != null) ...[
            const SizedBox(width: 2),
            Icon(trailing, size: 18, color: color),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: chip);
  }
}

/// 아이콘 · 제목 · 설명 · 오른쪽 끝(화살표/스위치)으로 된 한 줄. 카드 안에서 쓴다.
class FeatureRow extends StatelessWidget {
  const FeatureRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.titleColor = AppColors.ink,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(keepWords(title),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: titleColor)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(keepWords(subtitle!),
                        style: const TextStyle(fontSize: 14.5, color: AppColors.sub, height: 1.35)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 설정·그룹 화면 배경: 연한 민트 그라데이션과 오른쪽 위 둥근 무늬.
class MintBackground extends StatelessWidget {
  const MintBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE6F6F2), AppColors.background],
          stops: [0, 0.45],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -90,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x33BFE9DF)),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// 카드 안 줄 사이 구분선 (왼쪽은 아이콘 너비만큼 들여쓴다).
class InsetDivider extends StatelessWidget {
  const InsetDivider({super.key, this.indent = 20});
  final double indent;

  @override
  Widget build(BuildContext context) => Divider(indent: indent, endIndent: 20);
}
