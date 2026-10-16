import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../services/backend.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _signUp = false;
  bool _agreed = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    if (_signUp && (name.isEmpty || !_agreed)) {
      _show(name.isEmpty ? '이름을 입력해주세요.' : '개인정보처리방침에 동의해주세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_signUp) {
        await AuthService.signUp(email, password, name);
      } else {
        await AuthService.signIn(email, password);
      }
    } catch (e) {
      _show(Backend.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _show('이메일을 먼저 입력해주세요.');
      return;
    }
    try {
      await AuthService.resetPassword(email);
      _show('비밀번호 재설정 메일을 보냈습니다.');
    } catch (e) {
      _show(Backend.errorMessage(e));
    }
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      await AuthService.signInWithGoogle();
    } catch (e) {
      _show(Backend.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 8)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.location_on, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(AppConfig.appName,
                      textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('가족·친구와 서로의 위치를 확인하세요',
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: _busy
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.account_circle),
                    label: const Text('구글 계정으로 계속하기'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: '계속하면 '),
                      TextSpan(
                        text: '개인정보처리방침',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
                      ),
                      const TextSpan(text: '(위치정보 수집·공유 포함)에 동의하게 됩니다.'),
                    ]),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Row(children: [
                      Expanded(child: Divider()),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('또는 이메일')),
                      Expanded(child: Divider()),
                    ]),
                  ),
                  if (_signUp) ...[
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: '이름 (그룹 멤버에게 표시)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration:
                        const InputDecoration(labelText: '이메일', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: '비밀번호', border: OutlineInputBorder()),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_signUp)
                    CheckboxListTile(
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text.rich(TextSpan(children: [
                        TextSpan(
                          text: '개인정보처리방침',
                          style: TextStyle(
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
                        ),
                        const TextSpan(text: '에 동의합니다 (위치정보 수집·공유 포함)'),
                      ])),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_signUp ? '가입하기' : '로그인'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _signUp = !_signUp),
                    child: Text(_signUp ? '이미 계정이 있어요' : '처음이에요 · 회원가입'),
                  ),
                  if (!_signUp)
                    TextButton(onPressed: _reset, child: const Text('비밀번호를 잊으셨나요?')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
