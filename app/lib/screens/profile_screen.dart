import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/avatars.dart';
import '../widgets/ui.dart';

/// 그룹 멤버에게 보일 이름과 이모지 캐릭터를 정하는 화면.
/// 처음 가입했을 때는 저장할 때까지 닫을 수 없다([required]).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.initialName,
    this.initialAvatar,
    this.required = false,
  });

  final String initialName;
  final String? initialAvatar;
  final bool required;

  static Future<void> show(
    BuildContext context, {
    required String name,
    String? avatar,
    bool required = false,
  }) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            ProfileScreen(initialName: name, initialAvatar: avatar, required: required),
      ));

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: widget.initialName);
  late String _avatar = widget.initialAvatar ?? avatarChoices.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    AuthService.setProfile(name: name, avatar: _avatar);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.required,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 8,
          title: Row(
            children: [
              // 처음 정할 때는 닫을 수 없다
              if (!widget.required)
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close, size: 26),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              else
                const SizedBox(width: 16),
              const SizedBox(width: 12),
              const Text('프로필', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 132,
                        height: 132,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFA9EFE2)),
                        alignment: Alignment.center,
                        child: ClipOval(child: AvatarGlyph(_avatar, size: 116)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _name,
                      builder: (context, value, _) => TextField(
                        controller: _name,
                        maxLength: 20,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontSize: 16.5),
                        decoration: InputDecoration(
                          labelText: '이름 (예: 엄마, 아빠, 민준)',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          suffixIcon: value.text.isEmpty
                              ? null
                              : IconButton(icon: const Icon(Icons.close), onPressed: _name.clear),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('지도에 보일 캐릭터',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 14),
                    GridView.count(
                      crossAxisCount: 6,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        for (final id in avatarChoices)
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(() => _avatar = id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: id == _avatar ? AppColors.mint : const Color(0xFFE8ECEB),
                                border: Border.all(
                                  color: id == _avatar ? AppColors.primaryDark : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: LayoutBuilder(
                                builder: (context, box) => AvatarGlyph(id, size: box.maxWidth),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _name,
                  builder: (context, value, _) => FilledButton(
                    onPressed: value.text.trim().isEmpty ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: AppColors.primaryDark,
                      textStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    child: Text(widget.required ? '시작하기' : '저장'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
