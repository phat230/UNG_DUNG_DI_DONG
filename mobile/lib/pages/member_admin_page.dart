import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MemberAdminPage extends StatefulWidget {
  const MemberAdminPage({super.key});
  @override
  State<MemberAdminPage> createState() => _MemberAdminPageState();
}

class _MemberAdminPageState extends State<MemberAdminPage> {
  List<Map<String, dynamic>> items = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Api.getMembers();
      if (mounted)
        setState(() {
          items = result;
          error = null;
          loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          loading = false;
        });
    }
  }

  Future<void> _role(Map<String, dynamic> item) async {
    final roles = item['roles'] as List? ?? const [];
    final current = roles.isEmpty ? 'Member' : roles.first as String;
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Vai trò: ${item['displayName']}'),
        children: [
          for (final role in ['Admin', 'Member'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, role),
              child: Row(
                children: [
                  if (role == current) const Icon(Icons.check, size: 18),
                  const SizedBox(width: 8),
                  Text(role),
                ],
              ),
            ),
        ],
      ),
    );
    if (next == null) return;
    try {
      await Api.setMemberRole(item['id'] as String, next);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quản lý thành viên')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : ListView(
            children: [
              for (final item in items)
                ListTile(
                  title: Text(item['displayName'] as String),
                  subtitle: Text('${item['userName']} • ${item['email']}'),
                  leading: CircleAvatar(
                    child: Text(
                      (item['displayName'] as String).characters.first,
                    ),
                  ),
                  onTap: () => _role(item),
                  trailing: Switch(
                    value: item['isActive'] as bool,
                    onChanged: (v) async {
                      try {
                        await Api.setMemberActive(item['id'] as String, v);
                        await _load();
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    },
                  ),
                ),
            ],
          ),
  );
}
