import 'package:flutter/material.dart';

/// 프로필에서 고를 수 있는 캐릭터 그림 (assets/avatars/c01.png ~ c54.png).
final avatarChoices = [for (var i = 1; i <= 54; i++) 'c${i.toString().padLeft(2, '0')}'];

/// 캐릭터 그림 id 인지 (예전에 고른 이모지는 글자 그대로 보여준다).
bool isCharacter(String? avatar) => avatar != null && RegExp(r'^c\d{2}$').hasMatch(avatar);

String avatarAsset(String id) => 'assets/avatars/$id.png';

/// 프로필 캐릭터 한 개: 캐릭터 그림이면 이미지로, 아니면 이모지·이름 첫 글자로 그린다.
class AvatarGlyph extends StatelessWidget {
  const AvatarGlyph(this.value, {super.key, required this.size, this.textColor});

  final String value;

  /// 그림의 한 변 길이 (글자는 이보다 조금 작게)
  final double size;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    if (isCharacter(value)) {
      return Image.asset(
        avatarAsset(value),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
    return Text(value, style: TextStyle(fontSize: size * 0.8, height: 1.15, color: textColor));
  }
}
