import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AdminCreateMemberPage extends StatefulWidget {
  const AdminCreateMemberPage({super.key, required this.groups});
  final List<Map<String, dynamic>> groups;
  @override
  State<AdminCreateMemberPage> createState() => _AdminCreateMemberPageState();
}

class _AdminCreateMemberPageState extends State<AdminCreateMemberPage> {
  final username = TextEditingController(),
      name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  String role = 'Member';
  int? workspaceId;
  bool busy = false;
  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await Api.createAdminMember(
        username: username.text.trim(),
        displayName: name.text.trim(),
        email: email.text.trim(),
        password: password.text,
        role: role,
        workspaceId: workspaceId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tạo tài khoản')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Họ và tên',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: username,
          decoration: const InputDecoration(
            labelText: 'Tên đăng nhập',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Mật khẩu khởi tạo (tối thiểu 8 ký tự)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(
            labelText: 'Vai trò hệ thống',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Member', child: Text('Member')),
            DropdownMenuItem(value: 'Admin', child: Text('Admin')),
          ],
          onChanged: (v) => setState(() => role = v ?? 'Member'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: workspaceId,
          decoration: const InputDecoration(
            labelText: 'Nhóm (tùy chọn)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Tài khoản cá nhân'),
            ),
            for (final g in widget.groups)
              DropdownMenuItem(
                value: g['id'] as int,
                child: Text(g['name'] as String),
              ),
          ],
          onChanged: (v) => setState(() => workspaceId = v),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : _save,
          icon: const Icon(Icons.person_add),
          label: Text(busy ? 'Đang tạo…' : 'Tạo tài khoản'),
        ),
      ],
    ),
  );
}

