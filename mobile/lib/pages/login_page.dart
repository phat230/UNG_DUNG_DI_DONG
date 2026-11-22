import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/google_auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});
  final VoidCallback onLogin;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final user = TextEditingController();
  final pass = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();
  final groupName = TextEditingController();
  bool busy = false;
  bool register = false;
  bool obscurePassword = true;
  String accountType = 'Personal';
  String? error;

  Future<void> signInWithGoogle() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final token = await GoogleAuth.getIdToken();
      await Api.loginWithGoogle(token);
      widget.onLogin();
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> forgotPassword() async {
    final emailController = TextEditingController(
      text: user.text.contains('@') ? user.text.trim() : '',
    );
    final tokenController = TextEditingController();
    final passwordController = TextEditingController();
    var requested = false;
    var working = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Đặt lại mật khẩu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nhập email đã đăng ký. Chúng tôi sẽ gửi mã đặt lại mật khẩu đến email đó.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  enabled: !requested && !working,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email tài khoản',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (requested) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: tokenController,
                    enabled: !working,
                    decoration: const InputDecoration(
                      labelText: 'Mã đặt lại mật khẩu',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    enabled: !working,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu mới (ít nhất 8 ký tự, có số)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      setDialogState(() {
                        working = true;
                        dialogError = null;
                      });
                      try {
                        if (!requested) {
                          if (!emailController.text.trim().contains('@')) {
                            throw Exception('Hãy nhập email hợp lệ.');
                          }
                          final debugToken = await Api.requestPasswordReset(
                            emailController.text.trim(),
                          );
                          tokenController.text = debugToken ?? '';
                          setDialogState(() {
                            requested = true;
                          });
                        } else {
                          if (tokenController.text.trim().isEmpty)
                            throw Exception('Hãy nhập mã nhận được qua email.');
                          if (passwordController.text.length < 8 ||
                              !RegExp(
                                r'\d',
                              ).hasMatch(passwordController.text)) {
                            throw Exception(
                              'Mật khẩu cần ít nhất 8 ký tự và có ít nhất một chữ số.',
                            );
                          }
                          await Api.resetPassword(
                            emailController.text.trim(),
                            tokenController.text.trim(),
                            passwordController.text,
                          );
                          if (dialogContext.mounted)
                            Navigator.pop(dialogContext);
                          if (mounted)
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đổi mật khẩu thành công. Hãy đăng nhập bằng mật khẩu mới.',
                                ),
                              ),
                            );
                        }
                      } catch (e) {
                        setDialogState(
                          () => dialogError = e.toString().replaceFirst(
                            'Exception: ',
                            '',
                          ),
                        );
                      } finally {
                        setDialogState(() => working = false);
                      }
                    },
              child: working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(requested ? 'Đặt lại mật khẩu' : 'Gửi mã'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    tokenController.dispose();
    passwordController.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register)
        await Api.register(
          name.text.trim(),
          email.text.trim(),
          user.text.trim(),
          pass.text,
          accountType,
          accountType == 'Group' ? groupName.text.trim() : null,
        );
      await Api.login(user.text.trim(), pass.text);
      widget.onLogin();
    } catch (e) {
      final errStr = e.toString().replaceFirst('Exception: ', '');
      if (errStr.contains('Failed to fetch') ||
          errStr.contains('Connection refused') ||
          errStr.contains('SocketException')) {
        setState(
          () => error =
              'Không thể kết nối đến máy chủ API (${Api.baseUrl}).\nHãy đảm bảo bạn đã khởi động Backend: dotnet run --project server/TaskFlow.Api',
        );
      } else {
        setState(() => error = errStr);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff4f6fc),
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffeef1ff), Color(0xfff8f9ff), Color(0xfff4f6fc)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF0284C7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.32),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.task_alt_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'TaskFlow',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    register
                        ? 'Tạo không gian làm việc của bạn'
                        : 'Sắp xếp công việc. Giữ nhịp mỗi ngày.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 26),
                  Card(
                    elevation: 2,
                    shadowColor: const Color(0xff273465).withValues(alpha: .08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            register
                                ? 'Tạo tài khoản mới'
                                : 'Chào mừng trở lại',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 20),
                          if (register) ...[
                            TextField(
                              controller: name,
                              textCapitalization: TextCapitalization.words,
                              decoration: _authDecoration(
                                'Họ và tên',
                                Icons.badge_outlined,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _authDecoration(
                                'Email',
                                Icons.alternate_email,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'Personal',
                                  label: Text('Cá nhân'),
                                  icon: Icon(Icons.person_outline),
                                ),
                                ButtonSegment(
                                  value: 'Group',
                                  label: Text('Tạo nhóm'),
                                  icon: Icon(Icons.groups_outlined),
                                ),
                              ],
                              selected: {accountType},
                              onSelectionChanged: (v) =>
                                  setState(() => accountType = v.first),
                            ),
                            if (accountType == 'Group') ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: groupName,
                                decoration: _authDecoration(
                                  'Tên nhóm',
                                  Icons.group_work_outlined,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Bạn sẽ là trưởng nhóm và có thể giao việc cho thành viên tham gia bằng mã nhóm.',
                                  style: TextStyle(color: Colors.blueGrey),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: user,
                            decoration: _authDecoration(
                              register
                                  ? 'Tên đăng nhập'
                                  : 'Tên đăng nhập hoặc email',
                              Icons.person_outline,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: pass,
                            obscureText: obscurePassword,
                            decoration:
                                _authDecoration(
                                  'Mật khẩu',
                                  Icons.lock_outline,
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => obscurePassword = !obscurePassword,
                                    ),
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: busy ? null : submit,
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      register ? 'Tạo tài khoản' : 'Đăng nhập',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          if (!register) ...[
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: busy ? null : forgotPassword,
                                icon: const Icon(Icons.lock_reset),
                                label: const Text('Quên mật khẩu?'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: busy ? null : signInWithGoogle,
                              icon: const Icon(Icons.g_mobiledata, size: 28),
                              label: const Text('Tiếp tục với Google'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                          Center(
                            child: TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      register = !register;
                                      error = null;
                                    }),
                              child: Text(
                                register
                                    ? 'Đã có tài khoản? Đăng nhập'
                                    : 'Chưa có tài khoản? Đăng ký',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  InputDecoration _authDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
        ),
      );
}

