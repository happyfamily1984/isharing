import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/avatars.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      canPop: !widget.required,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.required,
          title: const Text('프로필'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(_avatar, style: const TextStyle(fontSize: 48)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _name,
                      builder: (context, value, _) => TextField(
                        controller: _name,
                        maxLength: 20,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: '이름 (예: 엄마, 아빠, 민준)',
                          border: const OutlineInputBorder(),
                          suffixIcon: value.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: _name.clear,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('지도에 보일 캐릭터', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 6,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (final emoji in avatarChoices)
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(() => _avatar = emoji),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: emoji == _avatar
                                    ? scheme.primaryContainer
                                    : scheme.surfaceContainerHighest,
                                border: Border.all(
                                  color: emoji == _avatar ? scheme.primary : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(emoji, style: const TextStyle(fontSize: 28)),
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
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
