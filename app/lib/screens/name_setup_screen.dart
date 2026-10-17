import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend.dart';

/// 구글로 처음 가입했을 때 그룹 멤버에게 보일 이름을 정하는 화면.
class NameSetupScreen extends StatefulWidget {
  const NameSetupScreen({super.key, required this.initialName});

  final String initialName;

  /// 이름을 저장할 때까지 닫을 수 없다.
  static Future<void> show(BuildContext context, String initialName) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NameSetupScreen(initialName: initialName),
      ));

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen> {
  late final _controller = TextEditingController(text: widget.initialName);
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AuthService.setDisplayName(name);
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(Backend.errorMessage(e))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false, title: const Text('이름 설정')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('그룹 멤버에게 보일 이름을 정해주세요', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('예: 엄마, 아빠, 민준. 나중에 설정에서 바꿀 수 있어요.',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 20,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: '이름',
                      border: const OutlineInputBorder(),
                      suffixIcon: value.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _controller.clear,
                            ),
                    ),
                  ),
                ),
                const Spacer(),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => FilledButton(
                    onPressed: _busy || value.text.trim().isEmpty ? null : _save,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const Text('시작하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
